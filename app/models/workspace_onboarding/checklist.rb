# The setup checklist an admin works through after the founder's letter, one step at a time and in order, until every
# step is done. An answer a person gives is kept on the row, so the checklist resumes where it was left on any device.
# Slack and the test incident are facts elsewhere and are read from there.
module WorkspaceOnboarding::Checklist
  extend ActiveSupport::Concern

  STEP_ACCOUNT = "account".freeze
  STEP_AI = "ai".freeze
  STEP_STACK = "stack".freeze
  STEP_PERMISSIONS = "permissions".freeze
  STEP_HALON = "halon".freeze
  STEP_SLACK = "slack".freeze
  STEP_TEST_INCIDENT = "test_incident".freeze
  CHECKLIST_STEPS = [ STEP_ACCOUNT, STEP_AI, STEP_STACK, STEP_PERMISSIONS, STEP_HALON, STEP_SLACK, STEP_TEST_INCIDENT ].freeze

  # done and skipped count as finished. A step up next or waiting may carry a note saying what holds it.
  STATE_DONE = "done".freeze
  STATE_SKIPPED = "skipped".freeze
  STATE_CURRENT = "current".freeze
  STATE_WAITING = "waiting".freeze
  STATES = [ STATE_DONE, STATE_SKIPPED, STATE_CURRENT, STATE_WAITING ].freeze
  FINISHED_STATES = [ STATE_DONE, STATE_SKIPPED ].freeze

  # Who pays for what Halon writes: the workspace's own key, its Firefight credits, or the keys the deployment runs on.
  AI_ACCOUNT = "account".freeze
  AI_CREDITS = "credits".freeze
  AI_HOUSE = "house".freeze
  AI_CHOICES = [ AI_ACCOUNT, AI_CREDITS, AI_HOUSE ].freeze
  HOUSE_PAYERS = [ Inference::PAID_BY_OPERATOR, Inference::PAID_BY_FIREFIGHT ].freeze

  ANSWER_CONNECTED = "connected".freeze
  ANSWER_UNUSED = "unused".freeze
  ANSWERS = [ ANSWER_CONNECTED, ANSWER_UNUSED ].freeze

  NO_WORKING_ACCOUNT = "Add an AI account whose check passes first.".freeze
  NO_CREDITS = "Firefight credits are not offered here.".freeze
  NO_CREDIT_BALANCE = "Buy Firefight credits first.".freeze
  NO_HOUSE = "This Firefight has no AI keys of its own to use.".freeze
  NOTHING_CONNECTED = "Connect one of these first.".freeze
  CHECK_FAILING = "The check on that connection did not pass yet. Fix it, or connect another.".freeze
  CATEGORY_REQUIRED = "Halon needs one of these to investigate, so connect at least one.".freeze
  NOT_YET = "Finish the steps above first.".freeze
  # A suggested first question names at most this many tools, past which it reads like a list.
  QUESTION_NAMES = 3
  # Said after a reason Halon cannot answer that the workspace fixes by choosing its AI again.
  FIX_IN_AI_STEP = "Change it under Choose Halon's AI.".freeze

  Step = Data.define(:key, :state, :note) do
    def finished? = FINISHED_STATES.include?(state)
  end

  included do
    validates :ai_choice, inclusion: { in: AI_CHOICES }, allow_nil: true
  end

  class_methods do
    # Why a category of the gallery cannot take that answer yet, or nil. card is one of IntegrationProvider.cards_for.
    def category_answer_blocked_reason(card, answer)
      case answer
      when ANSWER_UNUSED then CATEGORY_REQUIRED if card.category.required
      when ANSWER_CONNECTED
        return if card.rows.any? { |row| row.state == IntegrationProvider::STATE_CONNECTED }

        card.rows.any? { |row| row.state == IntegrationProvider::STATE_NEEDS_ATTENTION } ? CHECK_FAILING : NOTHING_CONNECTED
      else raise ArgumentError, "Unknown answer #{answer.inspect}"
      end
    end
  end

  # Admins only. Anyone else in the workspace goes straight to the dashboard while setup runs.
  def steers?(membership)
    checklist_completed_at.nil? && membership.present? &&
      membership.may?(Ability::Action::RESOURCE_WORKSPACE, Ability::Action::ACTION_UPDATE, workspace)
  end

  def steps
    current_found = false
    CHECKLIST_STEPS.map do |key|
      state, note = finished_state(key)
      unless state
        state = current_found ? STATE_WAITING : STATE_CURRENT
        note = current_found ? waiting_note(key) : current_note(key)
        current_found = true
      end
      Step.new(key: key, state: state, note: note)
    end
  end

  def current_step = steps.find { |step| step.state == STATE_CURRENT }

  def done? = steps.all?(&:finished?)

  # Stamped once, by whichever request sees the last step finish. Answers whether this call finished it.
  def finish_if_done!
    return false if checklist_completed_at || !done?

    finished = self.class.where(id: id, checklist_completed_at: nil).update_all(checklist_completed_at: Time.current, updated_at: Time.current)
    reload
    finished == 1
  end

  # What a person can choose for Halon's AI here: their own key always, and credits or the deployment's keys where they exist.
  def ai_choices
    [ AI_ACCOUNT, (AI_CREDITS if Entitlements.ai_credit(workspace)), (AI_HOUSE if house_ai?) ].compact
  end

  def ai_choice_blocked_reason(choice)
    case choice
    when AI_ACCOUNT then NO_WORKING_ACCOUNT unless workspace.workspace_ai_accounts.usable.where.not(verified_at: nil).exists?
    when AI_CREDITS then credits_blocked_reason
    when AI_HOUSE then NO_HOUSE unless house_ai?
    else raise ArgumentError, "Unknown AI choice #{choice.inspect}"
    end
  end

  def choose_ai!(choice)
    raise ArgumentError, "Unknown AI choice #{choice.inspect}" unless AI_CHOICES.include?(choice)

    self.class.where(id: id).update_all(ai_choice: choice, ai_chosen_at: Arel.sql("COALESCE(ai_chosen_at, now())"), updated_at: Time.current)
    reload
  end

  # Every category on the gallery, in its order, with what this workspace has connected in it.
  def stack_cards = IntegrationProvider.cards_for(workspace)

  # One statement merges the answer, so two tabs answering different categories keep both. The step is done once every
  # category on the gallery has an answer.
  def answer_category!(category, answer)
    self.class.where(id: id).update_all([ "stack_answers = stack_answers || jsonb_build_object(?::text, ?::text), updated_at = now()", category.slug, answer ])
    reload
    answered_all = IntegrationProvider.category_list.all? { |entry| stack_answers.key?(entry.slug) }
    stamp_once!(:stack_done_at) if answered_all
  end

  def review_permissions! = stamp_once!(:permissions_reviewed_at)

  # Called when Halon finishes an answer in a chat someone started on the dashboard. Only an admin's chat counts, since
  # only an admin works through setup.
  def halon_answered!(conversation)
    return if halon_answered_at || checklist_completed_at
    return unless conversation.personal? && conversation.started_by.is_a?(WorkspaceMembership) && steers?(conversation.started_by)

    self.class.where(id: id, halon_answered_at: nil).update_all(halon_answered_at: Time.current, updated_at: Time.current)
  end

  # What the chat shows an admin while Meet Halon is the step to do, or has just been done: the question to start with
  # and whether Halon answered. Nil once setup has moved past it or for anyone setup does not steer.
  def halon_guide(membership)
    return unless steers?(membership)

    step = steps.find { |candidate| candidate.key == STEP_HALON }
    return unless [ STATE_CURRENT, STATE_DONE ].include?(step.state)

    { question: first_question, answered: step.state == STATE_DONE }
  end

  # The question the chat suggests first, naming what was connected in the categories the registry marks for it, such
  # as where the stack runs and its databases. cards are stack_cards, passed when the page already read them.
  def first_question(cards = stack_cards)
    names = cards.select { |card| card.category.in_first_question && stack_answers[card.category.slug] == ANSWER_CONNECTED }
                       .flat_map { |card| card.rows.select { |row| row.state == IntegrationProvider::STATE_CONNECTED }.map { |row| row.provider.name } }
    return "What runs where in my stack?" if names.empty? || names.size > QUESTION_NAMES

    "What runs where in my stack across #{names.to_sentence(last_word_connector: ' and ')}?"
  end

  def skip_slack! = stamp_once!(:slack_skipped_at)

  private

  # Two tabs answering at once keep the first time.
  def stamp_once!(column)
    self.class.where(id: id, column => nil).update_all(column => Time.current, updated_at: Time.current)
    reload
  end

  def house_ai? = HOUSE_PAYERS.include?(AiFunding.house_payer(workspace)&.paid_by)

  # [state, note] for a step that needs nothing more, or nil while it waits on the person.
  def finished_state(key)
    case key
    when STEP_ACCOUNT then [ STATE_DONE, nil ]
    when STEP_AI then ai_chosen_at && [ STATE_DONE, nil ]
    when STEP_STACK then stack_done_at && [ STATE_DONE, nil ]
    when STEP_PERMISSIONS then permissions_reviewed_at && [ STATE_DONE, nil ]
    when STEP_HALON then halon_answered_at && [ STATE_DONE, nil ]
    when STEP_SLACK then slack_state
    when STEP_TEST_INCIDENT then test_incident_state
    end
  end

  # Meeting Halon is required, so a Halon that cannot answer yet holds the step and says why. A model it does not know is
  # fixed by choosing the AI again, so only that reason points back to the AI step.
  def current_note(key)
    return unless key == STEP_HALON

    reason = Investigation.unavailable_reason(workspace)
    return reason unless reason == Investigation::MODEL_NOT_SET_UP

    "#{reason} #{FIX_IN_AI_STEP}"
  end

  # Credits are a choice only once there is a balance to spend, since Halon's first answer comes straight after.
  def credits_blocked_reason
    credit = Entitlements.ai_credit(workspace)
    return NO_CREDITS unless credit

    NO_CREDIT_BALANCE unless credit.spendable?
  end

  def slack_state
    return [ STATE_DONE, nil ] if workspace.chat_connected?

    slack_skipped_at && [ STATE_SKIPPED, nil ]
  end

  # The test incident runs in Slack, so without it the step waits for Slack and holds nothing up.
  def test_incident_state
    return [ STATE_DONE, nil ] if first_incident

    reason = workspace.incidents_blocked_reason
    reason && slack_skipped_at && [ STATE_SKIPPED, reason ]
  end

  # A test incident waiting on Slack says so, whatever else is left before it.
  def waiting_note(key)
    (workspace.incidents_blocked_reason if key == STEP_TEST_INCIDENT) || NOT_YET
  end
end

# A step a coding agent asked permission for while it writes a change, such as repeating the same tool call. OpenCode
# asks only for what Fixing::PERMISSIONS marks ask, and the box puts each question to Firefight, which hands it to
# Halon. Halon lets the agent go on or refuses the step, with why, or, where the change was asked for in a chat or a
# fix, leaves it to the person as a question with the way it leans. The decision is kept with the change and shown on
# its step. Everything in the box runs as one user, so the agent can reach what answers OpenCode there. An answer that
# did not come from Firefight is never trusted: the box reports it, Firefight refuses the agent's next model call while
# its question is open, and either way the run stops and nothing is opened.
class CodeAgentPermission < ApplicationRecord
  STATUS_OPEN = "open"
  STATUS_ALLOWED = "allowed"
  STATUS_STOPPED = "stopped"
  # Answered by something in the box rather than by Firefight, such as the agent itself.
  STATUS_ANSWERED_IN_BOX = "answered_in_box"
  STATUSES = [ STATUS_OPEN, STATUS_ALLOWED, STATUS_STOPPED, STATUS_ANSWERED_IN_BOX ].freeze
  ANSWERED_IN_BOX = "The coding agent answered its own question about a step instead of waiting for Halon, so it was stopped and nothing is opened.".freeze

  # OpenCode's answers to a permission request (PermissionV1.Reply at 1.18.34). once lets this one step through and
  # asks again next time, reject refuses it, with the reason as feedback the model reads.
  REPLY_ONCE = "once".freeze
  REPLY_REJECT = "reject".freeze
  # OpenCode's own permission for a repeated tool call, asked once the same call comes this many times in a row
  # (DOOM_LOOP_THRESHOLD in session/processor.ts).
  REPEATED = "doom_loop".freeze
  REPEATED_TIMES = 3
  ASKED_LIMIT = 600
  REASON_LIMIT = 400
  STEPS_KEPT = 20
  ALLOW = "Let it continue".freeze
  STOP = "Stop it".freeze
  # Options of the question a person is asked, in this order, so the chosen index is the decision.
  OPTION_ALLOW = 0
  OPTION_STOP = 1

  belongs_to :session, class_name: "CodeAgentSession", foreign_key: :code_agent_session_id, inverse_of: :permissions
  belongs_to :workspace
  belongs_to :decided_by, polymorphic: true, optional: true
  has_one :question, class_name: "CodeAgentQuestion", foreign_key: :code_agent_permission_id, inverse_of: :permission, dependent: :delete

  # What the agent asked to do and the steps before it can quote the repository, so they are kept like a chat's messages.
  encrypts :asked, :steps, :reason
  serialize :steps, coder: JSON

  validates :status, inclusion: { in: STATUSES }

  scope :decided, -> { where.not(status: STATUS_OPEN) }
  scope :answered_in_box, -> { where(status: STATUS_ANSWERED_IN_BOX) }

  # The question for request_id, made once however often the box asks, since it asks again until it has an answer.
  # permission is OpenCode's name for it, patterns and metadata what OpenCode sent with it, and steps what the agent did
  # lately, one plain line each, and agent_session OpenCode's own session that asks. Answers whether it was made now.
  def self.ask!(session, request_id:, permission:, patterns:, metadata:, steps:, agent_session: nil)
    found = find_by(session: session, request_id: request_id.to_s)
    return [ found, false ] if found

    made = create!(session: session, workspace: session.workspace, request_id: request_id.to_s, permission: permission.to_s.first(100),
                   agent_session_id: agent_session.to_s.first(100).presence,
                   asked: Chat::SecretFree.redacted(describe(permission.to_s, Array(patterns).map(&:to_s), metadata.to_h)).truncate(ASKED_LIMIT),
                   steps: Array(steps).last(STEPS_KEPT).map { |step| Chat::SecretFree.redacted(step.to_s) })
    [ made, true ]
  rescue ActiveRecord::RecordNotUnique
    [ find_by!(session: session, request_id: request_id.to_s), false ]
  end

  # What the agent asks to do, in plain words, read after "The coding agent". A repeated call names what it repeats.
  def self.describe(permission, patterns, metadata)
    if permission == REPEATED
      tool = metadata["tool"].presence || patterns.first
      input = metadata["input"].to_h
      what = input["command"].presence || input["filePath"].presence || input["pattern"].presence || input.to_json
      return "repeated #{tool} #{REPEATED_TIMES} times in a row with the same input: #{what.to_s.squish}"
    end

    on = patterns.reject { |pattern| pattern == "*" }
    "asked to use #{permission}#{" on #{on.to_sentence}" if on.any?}"
  end

  def open? = status == STATUS_OPEN

  def answered_in_box? = status == STATUS_ANSWERED_IN_BOX

  # Something in the box answered OpenCode instead of Firefight, whatever Firefight decided, so the run cannot go on.
  def answered_in_box!
    self.class.where(id: id).where.not(status: STATUS_ANSWERED_IN_BOX)
        .update_all(status: STATUS_ANSWERED_IN_BOX, reason: nil, decided_by_type: nil, decided_by_id: nil, decided_at: Time.current, updated_at: Time.current)
    reload
  end

  def allowed? = status == STATUS_ALLOWED

  def by_halon? = decided_by.is_a?(SystemAgent)

  def decided_by_name = by_halon? ? CodeAgentQuestion::HALON : decided_by&.actor_display_name

  # One guarded update from open, so Halon and a person answering at once leave exactly one decision standing.
  def decide!(allow:, reason:, by:)
    moved = self.class.where(id: id, status: STATUS_OPEN)
                .update_all(status: allow ? STATUS_ALLOWED : STATUS_STOPPED, reason: reason.to_s.squish.truncate(REASON_LIMIT),
                            decided_by_type: by&.class&.polymorphic_name, decided_by_id: by&.id, decided_at: Time.current, updated_at: Time.current) == 1
    reload
    moved
  end

  # Settles it from the person's question once that settled: an option by its index, their own words as a refusal
  # the agent reads, nobody answering in time as the way Halon leaned, and a change that ended as a refusal.
  def settle_from_question!
    asked = question&.reload
    return false unless open? && asked && !asked.open?

    if asked.answered? && asked.chosen_option
      decide!(allow: asked.chosen == OPTION_ALLOW, reason: nil, by: asked.answered_by)
    elsif asked.answered?
      decide!(allow: false, reason: asked.answer, by: asked.answered_by)
    elsif asked.defaulted?
      decide!(allow: asked.recommended == OPTION_ALLOW, reason: "nobody answered in time and it leaned that way, since #{asked.recommended_reason.to_s.sub(/\A./, &:downcase)}",
              by: SystemAgent.investigator)
    else
      decide!(allow: false, reason: "The change ended before anyone answered.", by: nil)
    end
  end

  # What the box replies to OpenCode, or nil while it is still open.
  def reply
    return if open?

    { "reply" => allowed? ? REPLY_ONCE : REPLY_REJECT, "message" => (stopped_words unless allowed?) }.compact
  end

  # The step's line once it is decided, such as "OpenCode repeated bash 3 times in a row with the same input: rspec,
  # and Halon let it continue because it edits the code between runs". Halon gives its reason, and a person who wrote
  # words is quoted.
  def step_words
    return if open?
    return "OpenCode #{asked}, and the coding agent answered that itself instead of waiting for Halon, so it was stopped" if answered_in_box?

    said = "OpenCode #{asked}, and #{decider} #{allowed? ? 'let it continue' : 'stopped it'}"
    return said if reason.blank?

    by_halon? || decided_by.nil? ? "#{said} because #{reason.sub(/\A./, &:downcase).delete_suffix('.')}" : "#{said}, saying \"#{reason}\""
  end

  private

  def decider = decided_by_name || "Firefight"

  def stopped_words
    return ANSWERED_IN_BOX if answered_in_box?

    [ "#{decider} refused this step.", reason.presence ].compact.join(" ")
  end
end

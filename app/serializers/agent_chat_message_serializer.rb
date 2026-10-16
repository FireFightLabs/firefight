class AgentChatMessageSerializer < BaseSerializer
  object_as :message

  # What a finished step got back, the same shape the live step event carries (Chat::StepOutcome).
  OUTCOME_TYPE = "{ kind: string; said: string | null; lines: string[]; total: number; size: number; " \
                 "link: { provider: string; url: string } | null }".freeze

  # What a coding agent a step runs has done so far, the same shape live and saved (Chat::CodeFixProgress#to_h).
  PROGRESS_TYPE = "{ startedAt: string; live: boolean; total: number; lines: { text: string; at: string | null; result: string | null }[]; " \
                  "changed: string[]; tests: { command: string; passed: boolean }[]; " \
                  "files: { path: string; added: number | null; removed: number | null }[]; finishedAt: string | null; " \
                  "outcome: string | null; pullRequest: string | null; reason: string | null; " \
                  "question: { id: string; text: string; askedAt: string | null; answerDueAt: string | null; status: string; " \
                  "answer: string | null; answeredBy: string | null; byHalon: boolean; answeredAt: string | null; " \
                  "options: { label: string; consequence: string }[]; recommended: number | null; recommendedReason: string | null; chosen: number | null; timeoutOutcome: string | null; " \
                  "changedTo: string | null; changedBy: string | null; changedAt: string | null; changedChosen: number | null; changeable?: boolean; updatedAt: string | null } | null; " \
                  "checks: { name: string; status: string; reason: string | null }[]; " \
                  "review: { ran: boolean; right: boolean; findings: string[]; verified: string[]; unverified: string[]; unreviewed: string[]; " \
                  "summary: string | null; sentBack: boolean } | null; " \
                  "pause: { id: string; status: string; question: string; savedBranch: string | null; decidedBy: string | null; resumableUntil: string | null } | null }".freeze

  attributes(id: { type: :string }, role: { type: :string })

  # What a page of messages shows beside each one, read once for the whole page rather than once a message: which steps
  # drew a chart, what a coding agent did in each step, and what each reply read (Chat::Sources).
  class Page
    def initialize(messages)
      @messages = messages.to_a
    end

    # A call id repeats across a chat's messages with some models, so a chart is this message's only when it was drawn
    # after the message and before a later one made a call by the same id.
    def charted?(message, key)
      drawn = charted.fetch([ message.chat_id, key ], [])
      later = callers.fetch([ message.chat_id, key ], []).select { |at| at > message.created_at }.min
      drawn.any? { |at| at >= message.created_at && (later.nil? || at < later) }
    end

    def work(message, key) = works[[ message.chat_id, key ]]

    def sources(message) = sources_by_reply.fetch(message.id, [])

    def said_as(message) = said_as_by_message[message.id]

    # The whole answers this page's steps name as kept aside, by chat id and handle (Chat::StepOutcome.saved_texts).
    def saved
      @saved ||= Chat::StepOutcome.saved_texts(@messages.group_by(&:chat_id).transform_values { |messages| messages.flat_map(&:ruby_llm_tool_calls) })
    end

    def self.reply?(message) = message.role == Chat::Message::ROLE_ASSISTANT && message.content.present? && message.ruby_llm_tool_calls.empty?

    private

    def keys = @keys ||= @messages.flat_map { |message| message.ruby_llm_tool_calls.map(&:tool_call_id) }

    def chat_ids = @messages.map(&:chat_id).uniq

    def charted
      @charted ||= if keys.empty?
        {}
      else
        Chat::Chart.where(chat_id: chat_ids, tool_call_id: keys).pluck(:chat_id, :tool_call_id, :created_at)
                   .group_by { |chat_id, key, _at| [ chat_id, key ] }.transform_values { |rows| rows.map(&:last) }
      end
    end

    def callers
      @callers ||= @messages.flat_map { |message| message.ruby_llm_tool_calls.map { |call| [ [ message.chat_id, call.tool_call_id ], message.created_at ] } }
                            .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
    end

    def works
      @works ||= if keys.empty?
        {}
      else
        workspace_of = @messages.to_h { |message| [ message.chat_id, message.chat.workspace_id ] }
        read = Chat::StepProgress.where(chat_id: chat_ids, tool_call_id: keys).to_h { |kept| [ [ kept.chat_id, kept.tool_call_id ], kept.work ] }
        read.group_by { |(chat_id, _key), _work| workspace_of[chat_id] }.each do |workspace_id, works|
          Chat::CodeFixProgress.preload_records(works.map(&:last), workspace_id)
        end
        read.to_h { |(chat_id, key), work| [ [ chat_id, key ], work&.with_current_question(workspace_of[chat_id]) ] }
      end
    end

    def said_as_by_message = @said_as_by_message ||= Chat::TurnText.roles(@messages)

    def sources_by_reply
      @sources_by_reply ||= @messages.select { |message| self.class.reply?(message) }.group_by(&:chat_id).values
                                     .reduce({}) { |found, replies| found.merge(Chat::Sources.for_replies(replies)) }
    end
  end

  # Every message of the page reads its steps and sources from one Page.
  def self.many(messages, options = nil)
    options = (options || {}).merge(page: Page.new(messages))
    super(messages, options)
  end

  def page = options[:page] || memo.fetch(:page) { Page.new([ message ]) }

  # A person's message in a chat asked in the platform reads as the platform shows it, from the platform_texts handed in.
  type :string
  def body
    content = message.content.to_s
    message.role == Chat::Message::ROLE_USER ? options.fetch(:platform_texts, {}).fetch(message.as_written || content, content) : content
  end

  # Where the times Halon made room fall among the turns.
  type :string
  def created_at = message.created_at.utc.iso8601(3)

  # The model that wrote Halon's message, by its last call that answered, so people comparing models can tell them apart.
  # Nil for a person's message and for one saved before calls were kept.
  type "string | null"
  def model
    return nil unless message.role == Chat::Message::ROLE_ASSISTANT

    answered = message.ruby_llm_usages.sort_by(&:created_at).map(&:to_entry).reverse.find(&:succeeded?)
    answered && Conversation::ModelMenu.label(answered.model, provider: answered.provider)
  end

  # What Halon read in the turn this reply answers, listed under it (Chat::Sources). Only a reply that ends a turn, one
  # with words and no call after them, carries it.
  type "{ title: string; url: string | null }[]"
  def sources
    return [] unless Page.reply?(message)

    page.sources(message).map(&:to_h)
  end

  # Whether Halon's words are a question put to the person, a status line among the steps, or the turn's result
  # (Chat::TurnText). Nil for a person's message and for one with no words.
  type "string | null"
  def said_as = page.said_as(message)

  # Only a person's message carries files.
  has_many :attached_files, as: :attachments, serializer: AgentChatAttachmentSerializer

  # Same shape as the live step event, so a step reads the same either way.
  type "{ key: string; title: string; headline: string; asked: [string, string][]; status: string; kind: string; source: string | null; seconds: number; " \
       "card: { kind: string; category: string | null } | null; outcome: #{OUTCOME_TYPE} | null; progress: #{PROGRESS_TYPE} | null; " \
       "questionBlockedReason: string | null; questionChangeBlockedReason: string | null; pauseBlockedReason: string | null }[]"
  def tools
    chat = message.chat
    workspace = chat.workspace
    calls = message.ruby_llm_tool_calls.sort_by(&:created_at)
    works = calls.to_h { |call| [ call.tool_call_id, page.work(message, call.tool_call_id) ] }
    calls.filter_map do |call|
      step = Chat::Tools.step(call.name, call.arguments, workspace: workspace)
      next unless step

      status = self.class.step_status(call, calls)
      { key: call.tool_call_id, title: step.title, headline: step.headline, asked: step.asked,
        status: status, kind: Chat::Tools.kind(call.name, workspace, call.arguments), source: step.source,
        seconds: self.class.step_seconds(call, message, last: call == calls.last),
        card: (card_for(step, call)&.to_h if status == Conversation::LiveDelivery::STATUS_DONE || step.card&.shown_while_running?),
        outcome: (Chat::StepOutcome.for_call(call, chat, saved: page.saved)&.to_h if FINISHED.include?(status)),
        progress: works[call.tool_call_id]&.to_h,
        questionBlockedReason: works[call.tool_call_id]&.question_blocked_reason(chat.workspace_id, options[:member]),
        questionChangeBlockedReason: works[call.tool_call_id]&.question_change_blocked_reason(chat.workspace_id, options[:member]),
        pauseBlockedReason: works[call.tool_call_id]&.pause_blocked_reason(chat.workspace_id, options[:member]) }
    end
  end

  def card_for(step, call)
    step.card || (Chat::Tools.chart_card if page.charted?(message, call.tool_call_id))
  end

  # What the page adds up for "thought for n seconds", counted from when the model started this reply, so the time it
  # spent deciding counts as thinking too. Only the last call of a message carries it, or calls made together in one
  # reply would each count the same stretch.
  def self.step_seconds(call, message, last:)
    finished = call.result&.created_at
    return 0 unless last && finished

    (finished - message.created_at).round
  end

  FINISHED = [
    Conversation::LiveDelivery::STATUS_DONE, Conversation::LiveDelivery::STATUS_FAILED, Conversation::LiveDelivery::STATUS_NOT_FOUND,
    Conversation::LiveDelivery::STATUS_REFUSED, Conversation::LiveDelivery::STATUS_STOPPED
  ].freeze

  STEP_STATUS_BY_APPROVAL = {
    Chat::APPROVAL_REQUESTED => Conversation::LiveDelivery::STATUS_WAITING,
    Chat::APPROVAL_DENIED => Conversation::LiveDelivery::STATUS_CANCELLED,
    Chat::APPROVAL_WITHDRAWN => Conversation::LiveDelivery::STATUS_CANCELLED
  }.freeze

  # An approved call has not run while another asked with it is still open, since the turn resumes only once every
  # question is answered. It waits until then rather than spinning.
  def self.step_status(call, asked_with = [])
    STEP_STATUS_BY_APPROVAL.fetch(call.approval) do
      next failed_status(call) if call.failed
      next Conversation::LiveDelivery::STATUS_DONE if call.result_id.present?
      next Conversation::LiveDelivery::STATUS_WAITING if asked_with.any? { |other| other.approval == Chat::APPROVAL_REQUESTED }

      Conversation::LiveDelivery::STATUS_RUNNING
    end
  end

  def self.failed_status(call)
    kind = Chat::StepOutcome.kind_of(failed: true, failure_kind: call.failure_kind)
    Conversation::LiveDelivery::OUTCOME_STATUSES.fetch(kind)
  end
end

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
                  "options: { label: string; consequence: string }[]; recommended: number | null; recommendedReason: string | null; chosen: number | null } | null; " \
                  "checks: { name: string; status: string; reason: string | null }[]; " \
                  "review: { ran: boolean; right: boolean; findings: string[]; verified: string[]; unverified: string[]; unreviewed: string[]; " \
                  "summary: string | null; sentBack: boolean } | null; " \
                  "pause: { id: string; status: string; question: string; savedBranch: string | null; decidedBy: string | null; resumableUntil: string | null } | null }".freeze

  attributes(id: { type: :string }, role: { type: :string })

  type :string
  def body
    message.content.to_s
  end

  # Where the times Halon made room fall among the turns.
  type :string
  def created_at = message.created_at.utc.iso8601(3)

  # Only a person's message carries files.
  has_many :attached_files, as: :attachments, serializer: AgentChatAttachmentSerializer

  # Same shape as the live step event, so a step reads the same either way.
  type "{ key: string; title: string; headline: string; asked: [string, string][]; status: string; kind: string; seconds: number; " \
       "card: { kind: string; category: string | null } | null; outcome: #{OUTCOME_TYPE} | null; progress: #{PROGRESS_TYPE} | null; " \
       "questionBlockedReason: string | null; pauseBlockedReason: string | null }[]"
  def tools
    chat = message.chat
    workspace = chat.workspace
    calls = message.ruby_llm_tool_calls.sort_by(&:created_at)
    charted = chat.charts.unscope(:order).where(tool_call_id: calls.map(&:tool_call_id)).distinct.pluck(:tool_call_id).to_set
    works = chat.step_progresses.where(tool_call_id: calls.map(&:tool_call_id)).to_h { |kept| [ kept.tool_call_id, kept.work ] }
    calls.filter_map do |call|
      step = Chat::Tools.step(call.name, call.arguments, workspace: workspace)
      next unless step

      status = self.class.step_status(call, calls)
      { key: call.tool_call_id, title: step.title, headline: step.headline, asked: step.asked,
        status: status, kind: Chat::Tools.kind(call.name, workspace),
        seconds: self.class.step_seconds(call, message, last: call == calls.last),
        card: (card_for(step, call, charted)&.to_h if status == Conversation::LiveDelivery::STATUS_DONE),
        outcome: (Chat::StepOutcome.for_call(call, chat)&.to_h if FINISHED.include?(status)),
        progress: works[call.tool_call_id]&.to_h, questionBlockedReason: question_blocked_reason(chat, call, works[call.tool_call_id]),
        pauseBlockedReason: pause_blocked_reason(chat, works[call.tool_call_id]) }
    end
  end

  # Why whoever is looking cannot answer the coding agent's open question on this step, or nil.
  def question_blocked_reason(chat, call, work)
    return unless work&.waiting_for_answer?

    CodeAgentQuestion.find_by(id: work.question["id"], workspace_id: chat.workspace_id)&.answer_blocked_reason(Current.principal)
  end

  # Why whoever is looking cannot continue or stop the change paused on this step, or nil.
  def pause_blocked_reason(chat, work)
    return unless work&.pause

    CodeAgentSession::Pause.find_by(id: work.pause["id"], workspace_id: chat.workspace_id)&.decide_blocked_reason(Current.principal)
  end

  def card_for(step, call, charted)
    step.card || (Chat::Tools.chart_card if charted.include?(call.tool_call_id))
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
    Conversation::LiveDelivery::STATUS_REFUSED
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

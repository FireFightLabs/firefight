# What Halon did before it could not carry on, and where it stopped, so the people it was helping can pick up from there
# without it. Built from the calls the chat kept since the work began, in the words its steps are shown with. Nil when it
# had done nothing, since the reason it stopped is then the whole story.
class Chat::StoppedNote
  HEADING = "What I did before I stopped:".freeze
  # The latest steps are where someone picks up, so a long run names only how many came before them.
  SHOWN_STEPS = 12
  STOPPED_AFTER = "I stopped after the last of these, before I decided what to do next.".freeze

  SUFFIXES = {
    Chat::StepOutcome::KIND_FAILED => ", which failed",
    Chat::StepOutcome::KIND_NOT_FOUND => ", which found nothing",
    Chat::StepOutcome::KIND_REFUSED => ", which was refused"
  }.freeze

  # A call put to the person, or one they turned down, is not something Halon left running.
  DECIDED_ELSEWHERE = [ Chat::APPROVAL_REQUESTED, Chat::APPROVAL_DENIED, Chat::APPROVAL_WITHDRAWN ].freeze

  # How far back finished answers are looked for, since a turn that stopped has only its own steps after the last one.
  ANSWERS_READ = 20

  def self.for(chat, since:)
    return nil if chat.nil? || since.nil?

    new(chat, since).text
  end

  # A chat's turn began after the last answer Halon finished, which a retried job does not move. The empty reply RubyLLM
  # saves while a model writes is not an answer, and the words are encrypted, so they are read here rather than queried.
  def self.since_last_answer(chat)
    return nil if chat.nil?

    answers = chat.messages.where(role: Chat::Message::ROLE_ASSISTANT, nudge: false).where.not(id: chat.tool_calls.select(:message_id))
    finished = answers.reorder(created_at: :desc, id: :desc).limit(ANSWERS_READ).find { |message| message.content.present? }
    new(chat, finished&.created_at || chat.created_at).text
  end

  def initialize(chat, since)
    @chat = chat
    @since = since
  end

  def text
    steps = @chat.tool_calls.includes(:result).where(created_at: @since..).order(:created_at, :id).filter_map { |call| step_for(call) }
    return nil if steps.empty?

    shown = steps.last(SHOWN_STEPS)
    earlier = steps.size - shown.size
    lines = shown.map { |step| "- #{step[:line]}" }
    lines.unshift("- #{earlier} earlier #{"step".pluralize(earlier)}") if earlier.positive?
    # A blank line ends the list, or markdown reads the last sentence as part of its last item.
    "#{[ HEADING, *lines ].join("\n")}\n\n#{where_it_stopped(shown.last)}"
  end

  private

  def step_for(call)
    title = Chat::Tools.step(call.name, call.arguments, workspace: @chat.workspace)&.title
    return nil if title.blank?

    { title: title, running: running?(call), line: line_for(call, title) }
  end

  def line_for(call, title)
    return "#{title}, which was still running" if running?(call)

    change = Chat::Tools.kind(call.name, @chat.workspace) == Chat::Tools::KIND_ACT ? " (a change)" : ""
    "#{title}#{change}#{SUFFIXES[Chat::StepOutcome.kind_of(failed: call.failed, failure_kind: call.failure_kind)]}"
  end

  def running?(call) = call.result.nil? && !DECIDED_ELSEWHERE.include?(call.approval)

  def where_it_stopped(last)
    return STOPPED_AFTER unless last[:running]

    "I stopped while this was still running: #{last[:title]}. Check whether it finished before you try it again."
  end
end

# One helper's run, on its own thread: a chat of its own with the brief, the tools that read, and the loop until it
# replies with its report. What each turn spends is taken from the asking loop's purse as it happens.
class Chat::Helpers::Run
  # Steps of the helpers a page watches are told at most this often, since several helpers read at once. Starting and
  # ending are always told.
  TELL_EVERY = 1.0

  def initialize(helper, share:, max_spend_cents:, choice:)
    @helper = helper
    @share = share
    @max_spend_cents = max_spend_cents
    @choice = choice
    @counted = 0
  end

  def call
    choice = @choice
    @helper.update_columns(model: choice.model)
    chat = Chat.open!(owner: @helper, workspace: @helper.workspace, model_choice: choice)
    agent = Chat::Helpers::Agent.new(@helper, parent: @share.fresh_parent.call)
    chat.add_message(role: Chat::Message::ROLE_USER, content: question(agent))

    outcome = engine(choice).run(
      chat: chat, tools: tools(agent, chat), max_spend_cents: @max_spend_cents, canceled: @share.canceled,
      on_step: ->(_step) { tell }, memory: chat
    ) { |turn| spent(turn) }
    finish(outcome, chat)
  rescue StandardError => error
    Rails.logger.warn({ event: "chat_helper.failed", helper_id: @helper.id, error: error.class.name, reason: error.try(:reason) }.compact.to_json)
    @helper.finish!(Chat::Helper::STATUS_FAILED, ended_because: Chat::Helper::COULD_NOT, spent_micros: @counted)
  ensure
    @share.moved.call
  end

  private

  def engine(choice)
    FirefightAi::Helper.new(
      @helper.workspace, inferable: @share.inferable, member: @share.member, choice: choice,
      purpose: @helper.deep ? AiPurpose::INVESTIGATION : AiPurpose::HELPER
    )
  end

  # The tools a run of its own starts with, and every tool the asking chat already found that this helper may read with,
  # so it does not pay for turns finding them again.
  def tools(agent, chat)
    offer = Chat::Tools.offer_to(chat)
    [
      Chat::Tools::Open.new(agent, offer: offer), Chat::Tools::UseSkill.new(agent, offer: offer), *Chat::Tools::Docs.all(agent),
      Chat::Tools::ReadResult.new(agent), *Chat::Tools.memory(agent), *Chat::Tools::Web.all(agent)
    ] + Chat::Tools.known(agent, @helper.chat)
  end

  def question(agent)
    [
      "Your check: #{@helper.title}",
      @helper.brief,
      ("This is for #{agent.incident.identifier} #{agent.incident.name}." if agent.incident)
    ].compact.join("\n\n")
  end

  def spent(turn)
    @share.purse.add(turn.spent_micros - @counted)
    @counted = turn.spent_micros
    @helper.spent!(turns_used: turn.turns_used, spent_micros: @counted)
  end

  def tell
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    return if @told_at && now - @told_at < TELL_EVERY

    @told_at = now
    @share.moved.call
  end

  ENDINGS = {
    FirefightAi::AgentLoop::STATUS_OUT_OF_BUDGET => Chat::Helper::OUT_OF_BUDGET,
    FirefightAi::AgentLoop::STATUS_OUT_OF_TURNS => Chat::Helper::OUT_OF_TURNS,
    FirefightAi::AgentLoop::STATUS_CANCELED => Chat::Helper::STOPPED
  }.freeze

  def finish(outcome, chat)
    @share.purse.add(outcome.spent_micros - @counted)
    @counted = outcome.spent_micros
    report = chat.sent_messages.reload.where(role: Chat::Message::ROLE_ASSISTANT).last&.content.presence
    if outcome.status == FirefightAi::AgentLoop::STATUS_ANSWERED && report
      return @helper.finish!(Chat::Helper::STATUS_REPORTED, report: report, turns_used: outcome.turns_used, spent_micros: outcome.spent_micros)
    end

    status = outcome.status == FirefightAi::AgentLoop::STATUS_CANCELED ? Chat::Helper::STATUS_STOPPED : Chat::Helper::STATUS_FAILED
    @helper.finish!(status, ended_because: ENDINGS.fetch(outcome.status, Chat::Helper::COULD_NOT), turns_used: outcome.turns_used, spent_micros: outcome.spent_micros)
  end
end

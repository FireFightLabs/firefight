# One specialist's run, on its own thread like any helper's, holding only its kind's reads and ending with
# report_findings. What it proposes is kept with its record, for the asking turn to hand Halon the tool each names.
class Chat::Specialists::Run < Chat::Helpers::Run
  # Follows a report in plain words, which skipped report_findings, so Halon checks it before relying on it.
  UNCHECKED = "[It answered in plain words rather than with report_findings, so these lines and links were not checked against what it read.]".freeze

  private

  def question(agent)
    changes = changes(agent)
    offered = if changes.any?
      "Changes of your kind you may propose, which Halon decides on:\n#{changes.map { |change| "- #{change.name}: #{change.line}" }.join("\n")}"
    else
      "No change of your kind can be made here, so propose none."
    end
    [ "Halon's objective for you: #{@helper.brief}", ("This is for #{agent.incident.identifier} #{agent.incident.name}." if agent.incident), offered ].compact.join("\n\n")
  end

  def work(chat, agent, choice)
    @report = Chat::Specialists::Report.new(chat, changes: changes(agent))
    engine(choice).run(
      chat: chat, tools: @share.specialists.tools(agent, domain) + [ @report ], playbook: Chat::Specialists.instructions(domain),
      max_spend_cents: @max_spend_cents, canceled: @share.canceled, answered: -> { @report.taken? }, on_step: ->(_step) { tell }, memory: chat
    ) { |turn| spent(turn) }
  end

  def engine(choice)
    FirefightAi::Specialist.new(
      @helper.workspace, inferable: @share.inferable, member: @share.member, choice: choice,
      purpose: @helper.deep ? AiPurpose::INVESTIGATION : AiPurpose::HELPER
    )
  end

  def finish(outcome, chat)
    counted!(outcome)
    used = { turns_used: outcome.turns_used, spent_micros: outcome.spent_micros }
    return @helper.finish!(Chat::Helper::STATUS_REPORTED, report: @report.text, proposals: @report.proposals.map(&:to_h), **used) if @report&.taken?

    reply = last_reply(chat)
    return @helper.finish!(Chat::Helper::STATUS_REPORTED, report: "#{reply}\n#{UNCHECKED}", **used) if outcome.status == FirefightAi::AgentLoop::STATUS_ANSWERED && reply

    ended(outcome)
  end

  def domain = Chat::Specialists.domain(@helper.domain)

  def changes(agent) = @changes ||= @share.specialists.changes(agent, domain)
end

# A deploy carries every commit since the one before it, while a deploy list names each by its newest commit alone, so a
# deploy is easily blamed for its title and a rollback offered without knowing what it undoes. A deploy read says what
# the live deploy carried, read through the code host holding the repository the resource is built from. A rollback in a
# chat is first answered with what it undoes, migrations included, unless something Halon read already said so, and only
# then is the person asked. Each read is its own step through the gateway, as whoever the agent acts for.
module Chat::Tools::DeploySpan
  # The words a read or a rollback's answer says what rolling back to a deploy undoes in, by its short name, so a later
  # rollback to it knows Halon has seen it.
  def self.undo_lead(short) = "Rolling back to #{short} would undo"

  module_function

  def after(agent_run, spec, answered, text)
    return text unless spec.key == Integrations::Capabilities::DEPLOYS && answered && text.is_a?(String) && !agent_run.try(:follows_state?)

    deploys = Integrations::Capabilities::Deploys.deploys_of(answered.result)
    live, before = span_ends(deploys) if deploys
    return text unless live

    [ text, carried(agent_run, answered.call.resource, live, before) ].join("\n\n")
  end

  # What a rollback undoes, which sends it back to Halon before anyone is asked when Halon has not seen it. nil when
  # nothing can be read of it or Halon has seen it.
  def undone_refusal(agent_run, spec, given)
    return unless spec.key == Integrations::Capabilities::ROLLBACK && Chat::Tools::LookFirst.applies?(agent_run)

    asked = given.slice(Integrations::Capabilities::RESOURCE_ARG, Integrations::Capabilities::CONNECTION_ARG)
    call = Integrations::Capabilities.resolve(agent_run.workspace, Integrations::Capabilities::DEPLOYS, asked, callable(agent_run), principal: agent_run.acting_principal)
    deploys = Integrations::Capabilities::Deploys.deploys_of(read(agent_run, call)&.value) || []
    live = Integrations::Capabilities::Deploys.live(deploys)
    target = deploys.find { |deploy| named?(deploy, given["to"].to_s.strip) }
    return unless live&.commit && target&.commit && !Integrations::Capabilities::Deploys.same_commit?(live.commit, target.commit)
    return if seen?(agent_run.chat, undo_lead(target.short))

    found = compared(agent_run, call.resource, target, live)
    return unless found

    [ "Not asked yet. #{undo_lead(target.short)} every commit since it, up to #{live.short}, which #{call.resource.name} runs now.",
      found.framed,
      ("The old version would run against the database these migrations left." if found.range.migrations?),
      "Say what this undoes in the call's intent, so the person decides knowing it, and call rollback again if it is still the right fix." ].compact.join("\n")
  rescue Integrations::Capabilities::Unroutable, Integrations::Error, Unread
    nil
  end

  # The deploy serving now and the one before it with another commit, which bound what the live one carried.
  def span_ends(deploys)
    live = Integrations::Capabilities::Deploys.live(deploys) || deploys.first
    return unless live&.commit

    before = deploys.drop(deploys.index(live).to_i + 1).find { |deploy| deploy.commit && !Integrations::Capabilities::Deploys.same_commit?(deploy.commit, live.commit) }
    [ live, before ] if before
  end

  def carried(agent_run, resource, live, before)
    lead = "What the live deploy carried: #{live.short} went out after #{before.short}, so it carried every commit between them, not only the newest one its title names."
    found = compared(agent_run, resource, before, live)
    return "#{lead} What they changed was not read." unless found

    "#{lead}\n#{found.framed}\n#{undo_lead(before.short)} all of it#{', the database migrations included' if found.range.migrations?}."
  rescue Integrations::Capabilities::Unroutable => error
    "#{lead} What they changed was not read: #{error.message}"
  rescue Unread => error
    "#{lead} What they changed was not read.\n#{error.message}"
  rescue Integrations::Error => error
    "#{lead} What they changed was not read: #{error.message}"
  end

  # A comparison the code host failed, with its words framed under the tool that said them.
  class Unread < StandardError; end

  # What a comparison showed, framed as the code host's words with the step it was read in, since commit titles are
  # anyone's text.
  Compared = Data.define(:range, :tool_name, :step) do
    def framed = FirefightAi::Evidence.frame(tool_name, Integrations::Capabilities::Comparison.described(range), step: step)
  end

  def compared(agent_run, resource, base, head)
    call = Integrations::Capabilities.compare_call(agent_run.workspace, resource, base.commit, head.commit, callable(agent_run), principal: agent_run.acting_principal)
    outcome = read(agent_run, call)
    range = Integrations::Capabilities::Comparison.of(outcome&.value)
    Compared.new(range: range, tool_name: call.tool.model_facing_name, step: outcome.step) if range
  rescue Integrations::Error => error
    raise if call.nil?

    raise Unread, FirefightAi::Evidence.frame(call.tool.model_facing_name, error.message)
  end

  # A read nobody approves, so one an approval rule holds is left unread. The outcome carries the step a run cites.
  def read(agent_run, call)
    tool = call.tool
    return if Chat::ToolCall.held_by_rule?(workspace: agent_run.workspace, action_key: tool.action_key, scope: call.scope, params: call.arguments)

    agent_run.tool_call(action_key: tool.action_key, params: call.arguments, scope: call.scope, tool_name: tool.model_facing_name,
                        label: Chat::Tools.label(tool.model_facing_name, call.arguments, workspace: agent_run.workspace)) do
      call.present_result(tool.integration.executor.call(tool: tool, environment_row: call.environment_row, arguments: call.arguments, box_key: agent_run.code_box_key))
    end
  rescue AbilityGateway::Denied, AbilityGateway::PendingApproval
    nil
  end

  def callable(agent_run)
    principal = agent_run.acting_principal
    resolved = Ability::Resolver.resolve(principal, agent_run.workspace)
    Chat::Tools.switched_on_tools(agent_run).select { |tool| tool.callable_by?(principal, resolved) }
  end

  def named?(deploy, wanted)
    return false if wanted.empty?

    [ deploy.id, deploy.version, deploy.tag ].include?(wanted) || deploy.commit?(wanted)
  end

  # Whether something Halon read in this turn, or in the answer the person is agreeing to while it is fresh, already said
  # what rolling back to this deploy undoes.
  def seen?(chat, lead)
    person = chat.messages.where(role: Chat::Message::ROLE_USER, nudge: false).reorder(created_at: :desc).limit(2).pluck(:created_at)
    from = person.second && person.second >= Chat::Tools::LookFirst::PROPOSAL_FRESH_FOR.ago ? person.second : person.first
    said = chat.messages.where(role: Chat::Message::ROLE_TOOL)
    said = said.where(created_at: from..) if from
    said.find_each.any? { |message| message.content.to_s.include?(lead) }
  end
end

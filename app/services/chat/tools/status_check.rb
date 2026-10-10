# A provider's status page is a source Halon always checks when errors point outward. When the logs, errors or traces it
# read name an outside provider's host in lines that failed, such as a timeout calling api.stripe.com, that provider's
# status page is read at once and said beside the result, so an outage upstream is seen before Halon blames the team's
# own code. Each read is a web read through the gateway as whoever the agent acts for, a step a finding can cite, the
# same read check_status_page makes.
module Chat::Tools::StatusCheck
  READS = [ Integrations::Capabilities::LOGS, Integrations::Capabilities::ERRORS, Integrations::Capabilities::TRACES ].freeze

  module_function

  def after(agent_run, spec, text)
    return text unless READS.include?(spec.key) && text.is_a?(String)

    pointed = Upstream.pointed_at(text)
    return text if pointed.empty?

    [ text, *pointed.map { |found| note(agent_run, found) } ].join("\n\n")
  end

  def note(agent_run, found)
    entry = found.entry
    page = entry.status_page.url
    lead = "Failing lines here name #{found.host}, which is #{entry.name}'s."
    blocked = agent_run.workspace.web_lookup_blocked_reason
    return "#{lead} Its status page is #{page}, which Firefight cannot read here. #{blocked}" if blocked

    said = agent_run.tool_call(action_key: Ability::Action::WEB_READ, params: { "provider" => entry.name }, tool_name: Mcp::Tools::CHECK_STATUS_PAGE,
                               label: "Check #{entry.name}'s status page") do
      Integrations::StatusPages.words(Integrations::StatusPages.read(entry))
    end
    "#{lead} Its status page, read now:\n#{Chat::Tools.hand_over(agent_run, Mcp::Tools::CHECK_STATUS_PAGE, said)}"
  rescue Integrations::Error, ArgumentError => error
    "#{lead} Its status page #{page} could not be read: #{error.message}"
  rescue AbilityGateway::Denied, AbilityGateway::PendingApproval
    "#{lead} Its status page is #{page}."
  end
end

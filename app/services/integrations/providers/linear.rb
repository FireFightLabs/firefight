module Integrations
  module Providers
    Linear = Provider.new(key: "linear", issue_tracker: "Integrations::IssueTrackers::Linear",
                                source_links: "Integrations::SourceLinks::Linear",
                                pack: "Integrations::Packs::Linear",
                                agent_sessions: "Integrations::AgentSessions::Linear")
  end
end

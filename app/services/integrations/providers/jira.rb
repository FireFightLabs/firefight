module Integrations
  module Providers
    Jira = Provider.new(key: "jira", source_links: "Integrations::SourceLinks::Jira", issue_tracker: "Integrations::IssueTrackers::Jira",
                              pack: "Integrations::Packs::Jira")
  end
end

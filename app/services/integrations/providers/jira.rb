module Integrations
  module Providers
    Jira = Provider.new(key: "jira", source_links: "Integrations::SourceLinks::Jira", issue_tracker: "Integrations::IssueTrackers::Jira")
  end
end

module Integrations
  module Providers
    Linear = Provider.new(key: "linear", issue_tracker: "Integrations::IssueTrackers::Linear",
                                pack: "Integrations::Packs::Linear")
  end
end

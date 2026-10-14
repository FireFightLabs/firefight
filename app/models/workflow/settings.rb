# What a workflow's Settings page changes, the same whether it comes from the page, the API or MCP: its name and
# description, owning team, spending ceiling per run, most runs per hour, one live run per subject, what a change does in
# a freeze window and the all clear. Only what is given changes, and an empty value clears what may be empty.
module Workflow::Settings
  extend ActiveSupport::Concern

  KEYS = %w[name description owner_team_id cost_cap_cents runs_per_hour subject_key freeze_behaviour all_clear].freeze

  # The given settings as the model takes them, anything else left out.
  def self.normalized(given)
    settings = given.to_h.stringify_keys.slice(*KEYS)
    settings["cost_cap_cents"] = settings["cost_cap_cents"].presence if settings.key?("cost_cap_cents")
    settings["subject_key"] = settings["subject_key"].to_s.strip.presence if settings.key?("subject_key")
    settings["owner_team_id"] = settings["owner_team_id"].presence if settings.key?("owner_team_id")
    settings
  end

  def update_settings!(given) = update!(Workflow::Settings.normalized(given))

  # Every setting as it stands, as the API and MCP answer it.
  def settings_summary
    { id: id, name: name, slug: slug, description: description, owner_team_id: owner_team_id, cost_cap_cents: cost_cap_cents,
      runs_per_hour: runs_per_hour, subject_key: subject_key, freeze_behaviour: freeze_behaviour, all_clear: all_clear, page: Workflow::Links.page(self) }
  end
end

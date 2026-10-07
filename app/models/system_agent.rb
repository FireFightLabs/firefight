# Firefight's own agents. Global, unlike a customer's Agent, and with no API key.
class SystemAgent < ApplicationRecord
  include Principal

  SLUG_INVESTIGATOR = "investigator"
  # Reads what a connection reaches onto the resource map. It only runs tools that are switched on, with Firefight's own
  # fixed reads, so what it did is in the activity log under its name.
  SLUG_MAP_SWEEP = "map_sweep"
  # Checks that a connection reaches the account behind its server. It only runs tools that are switched on, with
  # Firefight's own fixed reads, so what it did is in the activity log under its name.
  SLUG_HEALTH_CHECK = "health_check"
  # Applies what changed in an issue tracker to the items its issues are linked to. It holds no grants and calls no tool,
  # so each change it makes is in the activity log under its name.
  SLUG_ISSUE_SYNC = "issue_sync"
  # Defined in code, so a fresh install and a test database get them without a migration.
  BUILT_IN = { SLUG_INVESTIGATOR => "Firefight Investigator", SLUG_MAP_SWEEP => "Firefight map sweep",
               SLUG_HEALTH_CHECK => "Firefight health check", SLUG_ISSUE_SYNC => "Firefight issue sync" }.freeze

  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :name, presence: true

  def self.investigator
    ensure!(SLUG_INVESTIGATOR)
  end

  def self.map_sweep
    ensure!(SLUG_MAP_SWEEP)
  end

  def self.health_check
    ensure!(SLUG_HEALTH_CHECK)
  end

  def self.issue_sync
    ensure!(SLUG_ISSUE_SYNC)
  end

  def self.ensure!(slug)
    find_by(slug: slug) || create!(slug: slug, name: BUILT_IN.fetch(slug))
  rescue ActiveRecord::RecordNotUnique
    find_by!(slug: slug)
  end

  # A listing is per workspace, and a global agent holds grants in many.
  attr_accessor :listing_workspace_id

  def ability_grants
    return super if listing_workspace_id.blank?

    super.where(workspace_id: listing_workspace_id)
  end

  def actor_display_name = name
  def actor_kind = Ability::Principal::KIND_SYSTEM_AGENT
  def platform_user_id = nil

  # Nobody authenticates as one, so no MCP session ever resolves to it.
  def mcp_readable?(_resource)
    false
  end
end

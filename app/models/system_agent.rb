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
  # Reads the documents synced handbook pages come from. It only runs tools that are switched on, with Firefight's own
  # fixed reads, so what it did is in the activity log under its name.
  SLUG_HANDBOOK_SYNC = "handbook_sync"
  # Raises a page in an on-call tool and keeps it in step with its incident. It holds only the tools each paging
  # connection needs for that, granted when the connection is made, so each call is in the activity log under its name.
  SLUG_PAGING = "paging"
  # Posts Halon's pull request reviews on the code host and answers on their threads. It holds only the tools each code
  # host connection posts a review through, granted when they are minted, so each call is in the activity log under its
  # name.
  SLUG_PULL_REQUEST_REVIEW = "pull_request_review"
  HALON = "Halon".freeze
  # Defined in code, so a fresh install and a test database get them without a migration.
  BUILT_IN = { SLUG_INVESTIGATOR => HALON, SLUG_MAP_SWEEP => "Firefight map sweep",
               SLUG_HEALTH_CHECK => "Firefight health check", SLUG_ISSUE_SYNC => "Firefight issue sync",
               SLUG_HANDBOOK_SYNC => "Firefight handbook sync", SLUG_PAGING => "Firefight paging",
               SLUG_PULL_REQUEST_REVIEW => "Halon pull request review" }.freeze

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

  def self.handbook_sync
    ensure!(SLUG_HANDBOOK_SYNC)
  end

  def self.paging
    ensure!(SLUG_PAGING)
  end

  def self.pull_request_review
    ensure!(SLUG_PULL_REQUEST_REVIEW)
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

  # Whoever asked for the run this agent works on, a member, an agent or a key, nil for a run nobody asked for. The agent
  # keeps its own grants and its name in the activity log, and makes no call they could not (AbilityGateway.permitted?).
  attr_reader :acting_for

  # This agent bounded by what starter may do and read, as their own chat or key would be. The same row to grants and the
  # ledger.
  def within_reach_of(starter) = clone.tap { |agent| agent.acting_for = starter }

  def actor_display_name = name
  def actor_kind = Ability::Principal::KIND_SYSTEM_AGENT
  def platform_user_id = nil

  protected

  attr_writer :acting_for

  public

  # Nobody authenticates as one, so no MCP session ever resolves to it.
  def mcp_readable?(_resource)
    false
  end
end

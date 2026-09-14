# Firefight's own agents. Global, unlike a customer's Agent, and with no API key.
class SystemAgent < ApplicationRecord
  include Principal

  SLUG_INVESTIGATOR = "investigator"
  # Defined in code, so a fresh install and a test database get them without a migration.
  BUILT_IN = { SLUG_INVESTIGATOR => "Firefight Investigator" }.freeze

  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :name, presence: true

  def self.investigator
    ensure!(SLUG_INVESTIGATOR)
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

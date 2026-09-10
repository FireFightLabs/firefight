# The interface every principal answers, human, token or agent. Grants attach to these.
module Principal
  extend ActiveSupport::Concern

  included do
    has_many :ability_grants, class_name: "Ability::Grant", as: :principal, dependent: :destroy
  end

  # A polymorphic actor cannot be eager-loaded with a nested user, only a
  # person has one.
  def self.preload_users(actors)
    people = actors.compact.grep(WorkspaceMembership)
    return if people.empty?

    ActiveRecord::Associations::Preloader.new(records: people, associations: [ :user ]).call
  end

  # A stable key the permissions UI explains and implicitly_allowed? enforces.
  # Keep the two in step.
  def implicit_authority
    :none
  end

  def principal_label
    "#{actor_kind}:#{actor_display_name}"
  end

  # Anything resolving to a human reads everything in the workspace.
  # Credential principals override.
  def mcp_readable?(_resource)
    true
  end

  # None by default, so credential principals act only on granted abilities.
  def implicitly_allowed?(_action)
    false
  end
end

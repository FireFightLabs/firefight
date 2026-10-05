# What Firefight's own agents hold when a workspace is installed. Each is an ordinary grant, so an admin narrows or
# revokes it on the Permissions screen like any other, and nothing here ever grants it back.
module Workspace::AgentDefaults
  extend ActiveSupport::Concern

  # A run locates what it investigates on the map before anything else, so it reads the map in every environment.
  INVESTIGATOR_DEFAULTS = [ Ability::Action::MAP_READ ].freeze

  def grant_agent_defaults!
    investigator = SystemAgent.investigator
    INVESTIGATOR_DEFAULTS.each do |key|
      action = Ability::Action.system!(key)
      ability_grants.find_or_create_by!(principal: investigator, action: action)
    end
  end
end

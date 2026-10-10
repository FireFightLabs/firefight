module Integrations
  # Who started what a call would stop or remove, as its provider says. A pack answers it from owner_of for its tools
  # that stop something (the registry's stopping_tools). name is how the provider names them, email their address when
  # the provider gives one, which is how a workspace member is matched, role one of ROLES, and what the
  # thing itself, such as "run 123 of Deploy in acme/shop".
  class Owner < Data.define(:name, :email, :role, :what)
    ROLE_STARTED = "started".freeze
    ROLE_DEPLOYED = "deployed".freeze
    ROLE_CREATED = "created".freeze
    ROLES = [ ROLE_STARTED, ROLE_DEPLOYED, ROLE_CREATED ].freeze

    def initialize(name:, role:, what:, email: nil) = super

    # The member who is this owner, matched by the address the provider gave, or nil.
    def member_in(workspace)
      return if email.blank?

      workspace.workspace_memberships.joins(:user).find_by("lower(users.email) = ?", email.to_s.strip.downcase)
    end
  end
end

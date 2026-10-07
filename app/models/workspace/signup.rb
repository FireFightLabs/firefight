# A workspace created from the dashboard, before any chat platform. It gets the same defaults an install gives, and
# the person who created it is its owner.
module Workspace::Signup
  extend ActiveSupport::Concern

  NAME_MAX_LENGTH = 80

  included do
    validates :name, length: { maximum: NAME_MAX_LENGTH }, on: :signup
  end

  class_methods do
    # invite_code is redeemed in the same transaction, so a code is spent only on a workspace that exists.
    def sign_up!(name:, user:, invite_code: nil)
      transaction do
        invite_code&.redeem!(user)
        workspace = new(name: name.to_s.strip, created_by: user)
        workspace.save!(context: :signup)
        workspace.setup_incident_configuration!
        workspace.setup_catalogue!
        workspace.grant_agent_defaults!
        membership = workspace.workspace_memberships.create!(user: user, role: :owner, joined_at: Time.current)
        workspace.create_onboarding!(installer: membership)
        membership
      end
    end
  end
end

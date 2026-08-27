class User < ApplicationRecord
  has_many :workspace_memberships, dependent: :destroy
  has_many :workspaces, through: :workspace_memberships

  validates :email, presence: true, uniqueness: true
  validates :name, presence: true

  def self.find_or_create_from_omniauth!(auth_hash)
    user = find_or_initialize_by(email: auth_hash.info.email)

    user.assign_attributes(
      name: auth_hash.info.name,
      avatar_url: auth_hash.info.image
    )

    user.save!
    user
  end

  # Sibling of `find_or_create_from_omniauth!` for the Slack OIDC flow.
  # OIDC auth hash uses different fields than OAuth v2 (no nested authed_user,
  # identity comes straight from `info`).
  def self.find_or_create_from_openid!(auth_hash)
    user = find_or_initialize_by(email: auth_hash.info.email)

    user.assign_attributes(
      name: auth_hash.info.name.presence || auth_hash.info.email,
      avatar_url: auth_hash.info.image
    )

    user.save!
    user
  end

  def member_of?(workspace)
    workspaces.include?(workspace)
  end

  def membership_in(workspace)
    workspace_memberships.find_by(workspace: workspace)
  end

  def owner_of?(workspace)
    membership_in(workspace)&.owner?
  end

  def admin_of?(workspace)
    membership_in(workspace)&.admin?
  end
end

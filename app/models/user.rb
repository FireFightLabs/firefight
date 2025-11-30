class User < ApplicationRecord
  # Associations
  has_many :workspace_memberships, dependent: :destroy
  has_many :workspaces, through: :workspace_memberships

  # Validations
  validates :email, presence: true, uniqueness: true
  validates :name, presence: true

  # Class Methods
  def self.find_or_create_from_omniauth!(auth_hash)
    find_or_create_by!(email: auth_hash.info.email) do |user|
      user.name = auth_hash.info.name
      user.avatar_url = auth_hash.info.image
    end
  end

  # Instance Methods
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

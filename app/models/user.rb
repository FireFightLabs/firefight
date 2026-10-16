class User < ApplicationRecord
  has_many :workspace_memberships, dependent: :destroy
  has_many :workspaces, through: :workspace_memberships
  has_many :identities, class_name: "UserIdentity", dependent: :destroy, inverse_of: :user

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, uniqueness: true
  validates :name, presence: true

  # The workspaces this person owns that no chat platform has connected yet, oldest first. A Slack sign-in from a team
  # no workspace has yet connects one of these rather than starting another.
  def owned_unconnected_memberships
    workspace_memberships.owner_role.joins(:workspace).merge(Workspace.chat_unconnected).includes(:workspace)
                         .order(Workspace.arel_table[:created_at])
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

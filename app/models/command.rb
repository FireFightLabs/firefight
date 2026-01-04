# Platform-agnostic command object
# Represents a command from any platform (Slack, Teams, etc.)
# This is a Plain Old Ruby Object (PORO), not an ActiveRecord model
class Command
  include ActiveModel::Model
  include ActiveModel::Validations

  attr_accessor :platform,      # String: 'slack', 'teams', etc.
                :workspace_id,   # UUID: Workspace ID in our database
                :user_id,        # String: Platform-specific user ID
                :text,           # String: Command text/arguments
                :trigger_id,     # String: Platform-specific trigger for modals
                :channel_id,     # String: Platform-specific channel ID
                :metadata        # Hash: Platform-specific additional data

  validates :platform, presence: true, inclusion: { in: %w[slack teams] }
  validates :workspace_id, presence: true
  validates :user_id, presence: true

  def initialize(attributes = {})
    @metadata = {}
    super
  end

  # Check if command has no text (empty command)
  def blank?
    text.blank?
  end

  # Get workspace record
  def workspace
    @workspace ||= Workspace.find_by(id: workspace_id)
  end

  # Check if command is from Slack
  def slack?
    platform == "slack"
  end

  # Check if command is from Teams
  def teams?
    platform == "teams"
  end

  # Get command arguments as array
  def args
    text.split(/\s+/)
  end

  # Get first word (subcommand)
  def subcommand
    args.first
  end
end

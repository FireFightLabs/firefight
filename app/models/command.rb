# Platform-agnostic command object
# Represents a command from any platform (Slack, Teams, etc.)
# This is a Plain Old Ruby Object (PORO), not an ActiveRecord model
class Command
  include ActiveModel::Model
  include ActiveModel::Validations

  EPHEMERAL = "ephemeral"

  def self.ephemeral(text, blocks: nil)
    { response_type: EPHEMERAL, text: text, blocks: blocks }
  end

  attr_accessor :platform,      # String: 'slack', 'teams', etc.
                :workspace_id,   # UUID: Workspace ID in our database
                :user_id,        # String: Platform-specific user ID
                :text,           # String: Command text/arguments
                :trigger_id,     # String: Platform-specific trigger for modals
                :channel_id,     # String: Platform-specific channel ID
                :metadata,       # Hash: Platform-specific additional data
                :approval_id     # UUID: set only when replaying an approved request

  validates :platform, presence: true, inclusion: { in: Platforms::ALL }
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

  def workspace
    @workspace ||= Workspace.find_by(id: workspace_id)
  end

  # Who the Ability Gateway authorizes this command as. Provisioned on demand
  # so a first-time caller is a principal like anyone else; nil when the
  # platform lookup fails and the dispatcher then refuses the call.
  def principal
    return @principal if defined?(@principal)

    @principal = WorkspaceMemberProvisioner.find_or_provision!(
      workspace: workspace, platform_user_id: user_id, adapter: workspace.adapter
    )
  rescue StandardError => e
    Rails.logger.warn({ event: "command.principal_unresolved", user_id: user_id, error: e.message }.to_json)
    @principal = nil
  end

  # What the approval digest is bound to. Deterministic and replayable: a
  # resumed command rebuilds the same hash, so the approval matches.
  def authorization_params
    { command: command_name, subcommand: subcommand, text: text }.compact
  end

  # The attrs a resumed dispatch is rebuilt from, once an approval clears.
  def resume_attrs
    {
      platform: platform, workspace_id: workspace_id, user_id: user_id,
      text: text, channel_id: channel_id, metadata: metadata
    }.compact
  end

  def incident
    @incident ||= workspace&.incidents&.active&.in_channel(channel_id)&.first
  end

  def slack?
    platform == Platforms::SLACK
  end

  def teams?
    platform == Platforms::TEAMS
  end

  # Get command arguments as array
  def args
    text.to_s.split(/\s+/)
  end

  # Get first word (subcommand)
  def subcommand
    args.first
  end

  # Get slash command name without leading "/"
  # e.g., "/firefight" → "firefight", "/ff" → "ff"
  def command_name
    metadata[:command]&.to_s&.delete_prefix("/")
  end
end

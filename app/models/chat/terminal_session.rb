# What lets one command in Halon's terminal call the workspace's connected tools through Firefight while it runs. The
# token is the only credential the box ever holds. It lasts as long as the command may run, and the row is removed once
# the command ends. Each call runs as the run that started the command would have run it, so the gateway, approval
# rules and the activity log treat it exactly as Halon's own call. A change goes through only when the person confirmed
# the command as one that changes something.
class Chat::TerminalSession < ApplicationRecord
  self.table_name = "chat_terminal_sessions"

  TOKEN_BYTES = 32
  # Time for the box to start and the command's answer to come back, on top of the command's own limit.
  MARGIN = 5.minutes
  # A script that loops over a provider can make many calls, but not without end.
  MAX_CALLS = 500
  ENDED = "This command has ended, so Firefight takes no more calls from it.".freeze
  TOO_MANY = "This command has made #{MAX_CALLS} calls through Firefight, the most one command may make.".freeze

  belongs_to :workspace
  # The conversation or investigation whose run started the command.
  belongs_to :owner, polymorphic: true
  # Whoever the run acts for, nil for an investigation, which acts as its own agent.
  belongs_to :principal, polymorphic: true, optional: true

  scope :live, -> { where(closed_at: nil).where("expires_at > ?", Time.current) }

  # The session and the token the box is handed, which is kept only as a digest. changes is whether the person
  # confirmed the command as one that changes something.
  def self.open!(agent_run, changes:, lasts:)
    where(expires_at: ...1.day.ago).delete_all
    token = SecureRandom.urlsafe_base64(TOKEN_BYTES)
    session = create!(
      workspace: agent_run.workspace, owner: agent_run.chat_owner, principal: (agent_run.acting_principal unless agent_run.chat_owner.is_a?(Investigation)),
      changes_allowed: changes && !agent_run.reads_only?, token_digest: digest(token), expires_at: (lasts + MARGIN).from_now
    )
    [ session, token ]
  end

  def self.authenticate(token)
    return if token.blank?

    live.find_by(token_digest: digest(token))
  end

  def self.digest(token) = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, token.to_s)

  # The command ended, so nothing it left running in the box can call through Firefight again.
  def finish! = self.class.where(id: id).delete_all

  # Claims one call, in SQL, so calls a script makes at once cannot slip past the limit together.
  def count_call! = self.class.where(id: id).where("calls < ?", MAX_CALLS).update_all([ "calls = calls + 1, updated_at = ?", Time.current ]) == 1

  # The run the calls are made as. The relay refuses a change the person did not confirm (Chat::Terminal::Relay), so a
  # conversation's turn is handed every tool the person may use and says why a change was not run.
  def agent_run
    case owner
    when Conversation then Conversation::Turn.new(owner, asker: principal)
    else owner
    end
  end
end

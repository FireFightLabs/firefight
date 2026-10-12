# The session in a tracker's issue a chat answers in, opened when someone assigned the issue to Firefight's app or
# mentioned it there (Integrations::AgentSessions). One session is one chat, kept with the connection it came through.
# asked_by is the member the tracker's person matched by email, whose chat list shows the chat.
class Conversation::IssueSession < ApplicationRecord
  self.table_name = "conversation_issue_sessions"

  belongs_to :conversation
  belongs_to :workspace
  belongs_to :integration
  belongs_to :asked_by, class_name: "WorkspaceMembership", optional: true

  validates :session_id, presence: true

  # Where people know the chat lives, the provider's own name.
  def place = IntegrationProvider.find(integration.provider)&.name || integration.name
end

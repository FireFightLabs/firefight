# One candidate cause Halon weighs while it troubleshoots in a chat: open while it is untested, confirmed or ruled out
# once the evidence settles it, with that evidence in Halon's words. One is the leading cause. The board is the chat's
# and is rewritten whole each time Halon updates it (replace!), keeping when each theory last moved, so a cause confirmed
# in the turn now running is told apart from one confirmed before (Conversation::Checks).
class Chat::Theory < ApplicationRecord
  STATUS_OPEN = "open".freeze
  STATUS_CONFIRMED = "confirmed".freeze
  STATUS_RULED_OUT = "ruled_out".freeze
  STATUSES = [ STATUS_OPEN, STATUS_CONFIRMED, STATUS_RULED_OUT ].freeze
  # The tool Halon keeps the board with (Chat::Tools::Theories), named here so a record of a chat can tell its calls apart.
  TOOL = "update_theories".freeze
  # Two or three is what a person can hold in mind, and what a turn can test at once.
  MAX = 3
  TITLE_LIMIT = 160
  EVIDENCE_LIMIT = 600

  belongs_to :chat
  belongs_to :workspace

  # Halon's words about what it read, which can quote a log line.
  encrypts :evidence

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :in_order, -> { order(:position) }

  def open? = status == STATUS_OPEN

  def confirmed? = status == STATUS_CONFIRMED

  Given = Data.define(:title, :status, :evidence, :leading)

  # The board as Halon gave it now, in its order. A theory keeps when its status last moved while it holds the same title
  # and status.
  def self.replace!(chat, given, tool_call_id:)
    transaction do
      before = where(chat: chat).index_by(&:title)
      where(chat: chat).delete_all
      given.first(MAX).each_with_index.map do |theory, index|
        title = theory.title.to_s.squish.truncate(TITLE_LIMIT)
        kept = before[title]&.then { |old| old.status_changed_at if old.status == theory.status }
        create!(chat: chat, workspace_id: chat.workspace_id, position: index + 1, title: title, status: theory.status,
                evidence: theory.evidence.to_s.squish.truncate(EVIDENCE_LIMIT).presence, leading: theory.leading == true,
                tool_call_id: tool_call_id, status_changed_at: kept || Time.current)
      end
    end
  end

  # The cause Halon leads with: the one it marked, or else the first.
  def self.leading_of(theories) = theories.find(&:leading) || theories.first
end

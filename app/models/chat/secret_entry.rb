# A secret a tool call in a chat moves without Halon seeing it. An entry asks the person who made the call to type a value
# that the tool then sends, such as a CI secret. A reveal shows that person a credential the tool made, such
# as a workflow's webhook address, read live from the provider each time. Both are drawn as a card under the step, and a
# chat in a Slack thread is pointed to the card. The row holds where the value goes or comes from (Integrations::
# SecretHandoffs), never the value, so it is not one of the places a secret is stored.
class Chat::SecretEntry < ApplicationRecord
  KIND_ENTER = "enter"
  KIND_REVEAL = "reveal"
  KINDS = [ KIND_ENTER, KIND_REVEAL ].freeze

  STATUS_PENDING = "pending"
  # Being sent, so a second submission does not send it twice.
  STATUS_SETTING = "setting"
  STATUS_SET = "set"
  STATUS_EXPIRED = "expired"
  # A reveal can be opened for as long as the provider still has what it names.
  STATUS_READY = "ready"
  STATUSES = [ STATUS_PENDING, STATUS_SETTING, STATUS_SET, STATUS_EXPIRED, STATUS_READY ].freeze

  # How long the field stays open, so a request nobody answered does not wait to be filled long after the chat moved on.
  OPEN_FOR = 1.hour

  belongs_to :chat
  belongs_to :tool, class_name: "Integration::Tool", foreign_key: :integration_tool_id, inverse_of: false
  belongs_to :requester, class_name: "WorkspaceMembership"
  belongs_to :done_by, class_name: "WorkspaceMembership", optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :title, presence: true
  validates :reference, presence: true, if: :reveal?

  scope :in_order, -> { order(:created_at, :id) }

  # The card for a tool's answer that asks for a value or names a credential, or nil for any other answer.
  def self.record_from!(result, chat:, tool_call_id:, tool:, catalog_entry_id:, requester:)
    entry = Integrations::SecretHandoffs.entry_of(result)
    reveal = Integrations::SecretHandoffs.reveal_of(result)
    common = { chat: chat, tool_call_id: tool_call_id, tool: tool, catalog_entry_id: catalog_entry_id, requester: requester }
    if entry && entry[Integrations::SecretHandoffs::VALUE_FROM].blank?
      create!(**common, kind: KIND_ENTER, status: STATUS_PENDING, title: entry[Integrations::SecretHandoffs::TITLE].to_s,
                        target: entry[Integrations::SecretHandoffs::TARGET].to_h, expires_at: OPEN_FOR.from_now)
    elsif reveal
      create!(**common, kind: KIND_REVEAL, status: STATUS_READY, title: reveal[Integrations::SecretHandoffs::TITLE].to_s,
                        reference: reveal[Integrations::SecretHandoffs::REFERENCE].to_s)
    end
  end

  def conversation = chat.owner

  def workspace = chat.workspace

  def enter? = kind == KIND_ENTER

  def reveal? = kind == KIND_REVEAL

  # A pending field past its hour reads expired, whether or not anything marked it.
  def shown_status = status == STATUS_PENDING && expires_at&.past? ? STATUS_EXPIRED : status

  def requester_name = requester.display_name

  def open? = [ STATUS_PENDING, STATUS_READY ].include?(shown_status)

  # Why this member cannot type the value now, or nil. The value is sent as whoever made the call, so only they can.
  def fill_blocked_reason(member)
    return "Only #{requester_name} can enter this value, since the change runs as them." unless member && member.id == requester_id

    case shown_status
    when STATUS_SET then "This value was already set."
    when STATUS_EXPIRED then "This field closed at #{clock(expires_at)}. Ask Halon again to set it."
    when STATUS_SETTING then "This value is being sent."
    end
  end

  def reveal_blocked_reason(member)
    return nil if member && member.id == requester_id

    "Only #{requester_name} can reveal this, since the call ran as them."
  end

  # Claimed by one submission at a time, while the field is open.
  def claim!
    won = self.class.where(id: id, status: STATUS_PENDING).where("expires_at > ?", Time.current)
              .update_all(status: STATUS_SETTING, updated_at: Time.current)
    reload
    won == 1
  end

  def filled!(by)
    self.class.where(id: id, status: STATUS_SETTING).update_all(status: STATUS_SET, done_by_id: by.id, done_at: Time.current, updated_at: Time.current)
    reload
  end

  # Sending failed, so the field opens again for another try.
  def released!
    self.class.where(id: id, status: STATUS_SETTING).update_all(status: STATUS_PENDING, updated_at: Time.current)
    reload
  end

  # The words on the card and in Slack.
  def headline = enter? && shown_status == STATUS_PENDING ? "Enter the value for #{title}" : title

  def body
    if enter?
      "Halon never sees it. Firefight sends it straight to #{tool.integration.display_name} and keeps no copy. Nothing is set until it is entered."
    else
      "It works like a password, so it is shown only here. Firefight reads it from #{tool.integration.display_name} each time and keeps no copy."
    end
  end

  # How it stands, or nil while it waits with nothing to say beyond its button.
  def status_line
    case shown_status
    when STATUS_SET then "Set by #{done_by&.display_name || 'someone who has left'} at #{clock(done_at)}."
    when STATUS_EXPIRED then "This field closed at #{clock(expires_at)}. Ask Halon again to set it."
    when STATUS_PENDING, STATUS_SETTING then "Open until #{clock(expires_at)}."
    end
  end

  # What Halon is told in place of the tool's own words, once the card is in the chat.
  def waiting_words
    "#{title} waits for its value. #{requester_name} types it in the secure field under this step, open until " \
      "#{clock(expires_at)}. You never see the value, and nothing is set until they do. Never ask for the value in the chat, " \
      "and if one is pasted there, say it was not used and point them to the field."
  end

  def at = created_at.utc.iso8601(3)

  private

  def clock(time) = time&.utc&.strftime("%H:%M UTC")
end

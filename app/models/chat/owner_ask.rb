# Whoever started what a call would stop or remove (Ability::Action::EFFECT_STOPS), when the provider says who and it
# is not the person asking. Once the person confirms the call, the owner is asked in a direct message, and the call runs
# only once they agree, through the usual approval after that. An owner Firefight cannot reach is named on the
# confirmation so the person checks with them first.
class Chat::OwnerAsk < ApplicationRecord
  STATUS_PENDING = "pending"
  STATUS_UNREACHABLE = "unreachable"
  STATUS_ASKED = "asked"
  STATUS_AGREED = "agreed"
  STATUS_DECLINED = "declined"
  STATUS_WITHDRAWN = "withdrawn"
  STATUSES = [ STATUS_PENDING, STATUS_UNREACHABLE, STATUS_ASKED, STATUS_AGREED, STATUS_DECLINED, STATUS_WITHDRAWN ].freeze
  # Shown in the chat once the owner was asked.
  SHOWN = [ STATUS_ASKED, STATUS_AGREED, STATUS_DECLINED, STATUS_WITHDRAWN ].freeze

  ROLE_WORDS = {
    Integrations::Owner::ROLE_STARTED => "Started by", Integrations::Owner::ROLE_DEPLOYED => "Last deployed by",
    Integrations::Owner::ROLE_CREATED => "Created by"
  }.freeze

  belongs_to :chat
  belongs_to :workspace
  belongs_to :owner, class_name: "WorkspaceMembership", optional: true
  belongs_to :confirmed_by, class_name: "WorkspaceMembership", optional: true
  # The scheduled plan whose run was asked from, which the owner's answer carries on with its approved-ahead tools.
  belongs_to :plan, class_name: "Chat::Plan", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :owner_role, inclusion: { in: Integrations::Owner::ROLES }

  scope :shown, -> { where(status: SHOWN) }

  def self.for_call(chat, tool_call_id) = chat && tool_call_id.present? ? find_by(chat: chat, tool_call_id: tool_call_id.to_s) : nil

  def conversation = chat.owner

  def pending? = status == STATUS_PENDING

  def asked? = status == STATUS_ASKED

  def agreed? = status == STATUS_AGREED

  def declined? = status == STATUS_DECLINED

  # Moves only from where it was, so a double click never answers twice. False when it had moved.
  def move!(from:, to:, **columns)
    moved = self.class.where(id: id, status: Array(from)).update_all(status: to, updated_at: Time.current, **columns)
    reload
    moved == 1
  end

  # What the confirmation says about the owner.
  def confirmation_row
    said = case status
    when STATUS_UNREACHABLE then "#{owner_name}, who Firefight cannot ask here. Check with them before you confirm."
    else "#{owner_name}, who is asked to agree once you confirm, before it runs."
    end
    [ ROLE_WORDS.fetch(owner_role), said ]
  end

  # Why this member may not answer, or nil. Only the owner answers for what they started.
  def answer_blocked_reason(member)
    return "This was already answered, or is no longer needed." unless asked?
    return nil if member && member == owner

    "Only #{owner_name} can answer this, since they #{owner_role} it."
  end

  # What the model reads when the owner said no, as the call's refusal.
  def declined_words = "Not run. #{owner_name}, who #{owner_role} #{what}, did not agree to it. Tell the person, and do not try it another way."

  # What it would stop, as the owner reads it, such as "workflow run 123 in acme/shop".
  def headline = "#{tool_name.to_s.tr('_', ' ').humanize} #{what}"
end

# An edit to a handbook page Halon proposed because a fresh reading contradicted it, such as releases running through a
# different tool than the page says, or a new page Halon drafted. Nothing changes until a person accepts it as written,
# edits it first, or dismisses it, from the card where Halon proposed it or on the Handbook page.
class Chat::HandbookProposal < ApplicationRecord
  include Chat::SecretFree

  self.table_name = "chat_handbook_proposals"

  STATUS_PENDING = "pending".freeze
  STATUS_ACCEPTED = "accepted".freeze
  STATUS_DISMISSED = "dismissed".freeze
  STATUSES = [ STATUS_PENDING, STATUS_ACCEPTED, STATUS_DISMISSED ].freeze

  # The handbook's wording and what showed it wrong reach every later prompt, like the handbook itself.
  encrypts :text, :evidence

  belongs_to :workspace
  # The page it changes. Nil for a new page, which title names.
  belongs_to :handbook_page, class_name: "Chat::HandbookPage", optional: true
  # The wording it would replace.
  belongs_to :instruction, class_name: "Chat::Instruction", optional: true
  # The wording accepting it wrote.
  belongs_to :result, class_name: "Chat::Instruction", optional: true
  belongs_to :conversation, optional: true
  belongs_to :investigation, optional: true
  belongs_to :incident, optional: true
  belongs_to :decided_by, class_name: "WorkspaceMembership", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :text, presence: true, length: { maximum: Chat::HandbookPage::TEXT_LIMIT }
  validates :evidence, presence: true
  validates :title, presence: true, length: { maximum: Chat::HandbookPage::TITLE_LIMIT }, unless: :handbook_page
  validate :page_takes_proposals, on: :create

  normalizes :title, with: ->(value) { value.to_s.squish.presence }

  scope :pending, -> { where(status: STATUS_PENDING) }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  # A proposal from a chat or run to change page, or to add a page called title.
  def self.propose!(owner, text:, evidence:, page: nil, title: nil)
    create!(workspace: owner.workspace, handbook_page: page, title: (title unless page), instruction: page&.current_wording, text: text,
            evidence: evidence, **owner_columns(owner), incident: owner.incident)
  end

  # What the same chat or run already proposed for that page, or for a new page of that title, still waiting.
  def self.waiting_from(owner, page: nil, title: nil)
    waiting = pending.where(owner_columns(owner))
    return waiting.find_by(handbook_page: page) if page

    waiting.where(handbook_page_id: nil).to_a.find { |proposal| proposal.title.casecmp?(title.to_s.squish) }
  end

  def self.owner_columns(owner) = owner.is_a?(Investigation) ? { investigation: owner } : { conversation: owner }

  # Decisions a chat or run has not been told yet, claimed once each so two turns never both tell the same one.
  def self.untold_for!(owner)
    where(owner_columns(owner)).where.not(status: STATUS_PENDING).where(told_at: nil).includes(:decided_by, :handbook_page).to_a
      .select { |proposal| where(id: proposal.id, told_at: nil).update_all(told_at: Time.current) == 1 }
  end

  def pending? = status == STATUS_PENDING

  def new_page? = handbook_page_id.nil?

  # The page's title, or the new page's.
  def page_title = handbook_page&.title || title

  # The wording the page holds now, which is what people compare the proposal with. Nil for a new page.
  def current_wording = handbook_page&.current_wording&.text

  def accept_blocked_reason
    return decided_sentence unless pending?

    stale_sentence if stale?
  end

  def dismiss_blocked_reason = (decided_sentence unless pending?)

  # Writes the proposed wording, or what the person edited it to, keeping the old wording as history, or adds the new
  # page. One guarded update decides who wins when two people press at once. Nil when it was decided first or the page
  # changed since.
  def accept!(by:, text: nil)
    wording = text.to_s.strip.presence || self.text
    written = transaction do
      next unless claim!(STATUS_ACCEPTED, by: by, edited: wording != self.text)

      write!(wording, by).tap { |note| raise ActiveRecord::Rollback unless note }
    end
    unless written
      reload
      return nil
    end

    update_columns(result_id: written.id, handbook_page_id: written.handbook_page_id)
    written
  end

  def dismiss!(by:) = claim!(STATUS_DISMISSED, by: by, edited: false)

  # How it was settled, as a card and the Handbook page say it, such as "Accepted by Ana Ruiz."
  def decided_sentence
    by = decided_by ? " by #{decided_by.display_name}" : ""
    case status
    when STATUS_ACCEPTED then edited ? "Accepted with an edit#{by}." : "Accepted#{by}."
    when STATUS_DISMISSED then "Dismissed#{by}."
    end
  end

  # Where Halon proposed it, as the Handbook page says it, such as "a chat in INC-12".
  def origin
    if investigation
      investigation.incident ? "the #{investigation.incident.identifier} investigation" : "an investigation"
    elsif conversation&.personal?
      "a chat with #{conversation.started_by.try(:display_name) || 'someone'}"
    elsif incident
      "a chat in #{incident.identifier}"
    else
      "a chat"
    end
  end

  # Such as "edit to the handbook page How we release" or "new handbook page Who owns what".
  def what = title.present? ? "new handbook page #{title}" : "edit to the handbook page #{page_title}"

  # What Halon is told at its next turn, so it never repeats a proposal already settled.
  def outcome_note
    who = decided_by&.display_name || "Someone"
    case status
    when STATUS_ACCEPTED
      edit = edited ? " after editing it" : ""
      "#{who} accepted your proposed #{what}#{edit}. Follow the handbook as it now reads."
    when STATUS_DISMISSED
      "#{who} dismissed your proposed #{what}. Keep following the handbook as written, and do not propose the same again."
    end
  end

  private

  def stale?
    return Chat::HandbookPage.where(workspace_id: workspace_id).where("lower(title) = ?", title.to_s.downcase).exists? if new_page?

    Chat::Instruction.current.where(handbook_page_id: handbook_page_id).pick(:id) != instruction_id
  end

  def stale_sentence
    return "A page called #{title} was added since Halon proposed it. Read the handbook again before deciding." if new_page?

    "Someone changed #{page_title} since Halon proposed this. Read the handbook again before deciding."
  end

  def page_takes_proposals
    blocked = handbook_page&.proposal_blocked_reason
    errors.add(:base, blocked) if blocked
  end

  def claim!(status, by:, edited:)
    now = Time.current
    won = self.class.where(id: id, status: STATUS_PENDING)
                    .update_all(status: status, decided_by_id: by&.id, decided_at: now, edited: edited, updated_at: now) == 1
    reload if won
    won
  end

  # Revises the wording the proposal was made against, or adds the new page. Nil when someone changed the page first.
  def write!(wording, by)
    return instruction&.revise!(text: wording, by: by) unless new_page?

    Chat::HandbookPage.create_written!(workspace, title: title, text: wording, by: by).current_wording
  end
end

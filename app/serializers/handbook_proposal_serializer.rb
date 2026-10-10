# A handbook edit or new page Halon proposed, as the Handbook page and the card in a chat show it. It carries what the
# page says now, what Halon would write, what showed it, and how it was settled. The blocked reasons decide which answers are
# offered.
class HandbookProposalSerializer < BaseSerializer
  object_as :proposal

  type :string
  def id = proposal.id

  type :string
  def page_title = proposal.page_title.to_s

  # It adds a page rather than changing one.
  type :boolean
  def new_page = proposal.title.present?

  # Nil for a new page.
  type :string, optional: true
  def current_wording = proposal.pending? ? proposal.current_wording : proposal.instruction&.text

  type :string
  def text = proposal.result&.text || proposal.text

  type :string
  def evidence = proposal.evidence

  # Such as "a chat in INC-12".
  type :string
  def origin = proposal.origin

  # When Halon proposed it, which places its card after the turn that found it.
  type :string
  def at = proposal.created_at.utc.iso8601(3)

  # How it was settled, or nil while it waits.
  type :string, optional: true
  def decided = proposal.decided_sentence

  type :string, optional: true
  def accept_blocked_reason = proposal.accept_blocked_reason

  type :string, optional: true
  def dismiss_blocked_reason = proposal.dismiss_blocked_reason
end

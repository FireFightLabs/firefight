# A memory something contradicted in this chat, asked about where the person read it: what Halon remembered, where it
# came from, what showed otherwise, and how it was settled. The blocked reasons decide which answers the card offers.
class AgentChatMemoryQuestionSerializer < BaseSerializer
  object_as :post

  type :string
  def id = post.id

  # Nil once someone deleted the memory on the Memory page.
  type :string, optional: true
  def memory_id = memory&.id

  type :string, optional: true
  def remembered = memory&.text

  # Such as "your chat" or "the INC-12 investigation".
  type :string, optional: true
  def origin = memory&.origin_for(options[:member])

  type :string, optional: true
  def learned_at = memory&.created_at&.utc&.iso8601

  # Such as "confirmed by Ana" or "not confirmed yet".
  type :string, optional: true
  def trust = memory&.trust_for(options[:member])

  # What showed it wrong, such as "The deploy log of web shows "web deploys from release"."
  type :string
  def evidence = post.evidence.to_s

  # How it was settled, or nil while it waits.
  type :string, optional: true
  def decided = memory&.decided_for(options[:member])

  type :string, optional: true
  def confirm_blocked_reason = memory&.confirm_blocked_reason

  type :string, optional: true
  def reject_blocked_reason = memory&.reject_blocked_reason

  type :string
  def at = post.created_at.utc.iso8601(3)

  private

  def memory = memo.fetch(:memory) { post.memories.first }
end

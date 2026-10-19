# A skill Halon proposed, as the Skills page and the card in the chat show it: what the skill says now, what Halon would
# make it say, why, and how it was settled.
class HalonSkillProposalSerializer < BaseSerializer
  object_as :proposal

  CONTENT_TYPE = HalonSkillSerializer::CONTENT_TYPE

  type :string
  def id = proposal.id

  type :string
  def name = proposal.custom_skill.name

  # It would add a skill rather than change one the workspace has.
  type :boolean
  def new_skill = proposal.parent_version.nil?

  # The library skill a new copy would be made from.
  type :string, optional: true
  def copy_of = proposal.custom_skill.library_name

  type :string
  def reason = proposal.reason.to_s

  # Such as "a chat with Alice".
  type :string
  def origin
    conversation = proposal.conversation
    return "a chat" unless conversation

    conversation.personal? ? "a chat with #{conversation.started_by.try(:actor_display_name) || 'someone'}" : "a chat"
  end

  # When Halon proposed it, which places its card after the turn that wrote it.
  type :string
  def at = proposal.created_at.utc.iso8601(3)

  # What the skill said when Halon proposed this, or nil for a new skill.
  type "#{CONTENT_TYPE} | null"
  def current
    base = proposal.parent_version
    base && { usedWhen: base.used_when, tools: base.tools, steps: base.steps }
  end

  type CONTENT_TYPE
  def proposed = { usedWhen: proposal.used_when, tools: proposal.tools, steps: proposal.steps }

  # How it was settled, or nil while it waits.
  type :string, optional: true
  def decided = proposal.decided_sentence

  type :string, optional: true
  def accept_blocked_reason = proposal.custom_skill.accept_blocked_reason(proposal)

  # Why editing it first cannot rename the skill, or nil.
  type :string, optional: true
  def rename_blocked_reason = proposal.custom_skill.accept_rename_blocked_reason(proposal)

  # Whether it can still be edited before accepting, which a decided one cannot.
  type :boolean
  def open = proposal.proposed?
end

# One of the workspace's own skills as the Skills page lists it: what it says now, its version and who wrote it, where it
# came from, whether Firefight shipped a newer version of a copy and what changed, and why it cannot be deleted or renamed.
class HalonSkillSerializer < BaseSerializer
  object_as :skill

  CONTENT_TYPE = "{ usedWhen: string; tools: string[]; steps: string }".freeze

  type :string
  def id = skill.id

  type :string
  def name = skill.name

  # Switched on, so Halon loads it.
  type :boolean
  def enabled = skill.enabled?

  type :string
  def used_when = skill.live_version.used_when

  type "string[]"
  def tools = skill.live_version.tools

  type :string
  def steps = skill.live_version.steps

  # The guides and signals a copy of a provider's skill keeps from Firefight's, which the editor carries over unchanged.
  type "string[]"
  def references = skill.live_version.references

  type "string[]"
  def signals = skill.live_version.signals

  type :string
  def version_id = skill.live_version.id

  type :number
  def version = skill.live_version.number

  # How many versions went live, which deleting it loses.
  type :number
  def version_count = skill.versions.count { |version| version.status.in?([ Chat::CustomSkill::Version::STATUS_LIVE, Chat::CustomSkill::Version::STATUS_RETIRED ]) }

  type :string
  def updated_by = skill.live_version.author_words

  type :string
  def updated_at = skill.live_version.created_at.utc.iso8601

  # The library skill it is a copy of, and the library version it holds.
  type :string, optional: true
  def copy_of = skill.library_name

  type :number, optional: true
  def library_version = skill.library_version

  # Firefight's newer version of a copy, with what the copy came from and what the newer one says.
  type "{ version: number; before: #{CONTENT_TYPE}; after: #{CONTENT_TYPE} } | null"
  def library_update
    newer = skill.library_update
    return unless newer

    base = skill.library_base.to_h
    { version: newer.version, before: { usedWhen: base["when"].to_s, tools: Array(base["tools"]), steps: base["steps"].to_s },
      after: { usedWhen: newer.used_when, tools: newer.tools, steps: newer.steps } }
  end

  # How many workflows run it.
  type :number
  def usage_count = skill.usage_count

  type :string, optional: true
  def deletion_blocked_reason = skill.deletion_blocked_reason

  type :string, optional: true
  def rename_blocked_reason = skill.rename_blocked_reason
end

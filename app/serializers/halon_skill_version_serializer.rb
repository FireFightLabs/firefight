# One version in a skill's history: what it said, who wrote it and why, and whether it can be brought back.
class HalonSkillVersionSerializer < BaseSerializer
  object_as :version

  type :string
  def id = version.id

  type :number
  def number = version.number

  type "'live' | 'retired' | 'dismissed' | 'edited'"
  def status = version.status

  type :string
  def author = version.author_words

  type :string, optional: true
  def reason = version.reason

  type :string
  def at = version.created_at.utc.iso8601

  type :string
  def used_when = version.used_when

  type "string[]"
  def tools = version.tools

  type :string
  def steps = version.steps

  # Only a version that was live can come back, and the live one already is.
  type :string, optional: true
  def restore_blocked_reason
    return "This is the live version." if version.live?
    return "Halon's proposal never went live, so it cannot be restored." unless version.status == Chat::CustomSkill::Version::STATUS_RETIRED

    nil
  end
end

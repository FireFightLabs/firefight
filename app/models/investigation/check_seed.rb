# The facts for a scheduled check: what it looks at, the notes people wrote for it, the skill that says how, and what
# Halon already raised from it, so a problem keeps its name from run to run and is said again only when it got worse.
class Investigation::CheckSeed
  # What was raised before is listed back this far.
  RAISED_WITHIN = 60.days
  RAISED_LIMIT = 30

  def initialize(investigation)
    @investigation = investigation
    @check = investigation.check
  end

  def gather
    kind = @check.kind_details
    {
      Investigation::Seeding::KEY_GATHERED_AT => Time.current.iso8601,
      "check" => {
        "name" => @check.name, "looks_at" => kind.description, "notes" => @check.notes, "skill" => kind.skill,
        "today" => Time.current.in_time_zone(@check.zone).to_date.iso8601
      }.compact,
      "already_raised" => raised,
      "billing" => (billing if @check.kind == Investigation::Check::KIND_COST)
    }.compact
  end

  private

  def raised
    @check.notices.where(last_seen_at: RAISED_WITHIN.ago..).includes(:resource).recent.limit(RAISED_LIMIT).map do |notice|
      {
        "signal" => notice.signal, "topic" => notice.topic, "resource" => notice.resource&.id, "severity" => notice.severity,
        "due_on" => notice.due_on&.iso8601, "summary" => notice.summary, "last_seen" => notice.last_seen_at.to_date.iso8601
      }.compact
    end
  end

  # Which connected providers report spend, by the skill that reads it, and which do not, so the run says what it could
  # not see rather than calling the bill flat.
  def billing
    coverage = Chat::Skill.coverage(@investigation.workspace, Chat::Skill::SIGNAL_COST)
    {
      "skills" => coverage.skills.map(&:name),
      "not_reported_by" => coverage.unread.filter_map { |key| IntegrationProvider.find(key)&.name }.sort
    }
  end
end

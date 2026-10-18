# The facts for a scheduled check: what it looks at, the notes people wrote for it, the skill that says how, and what
# Halon already raised from it, so a problem keeps its name from run to run and is said again only when it got worse.
class Investigation::CheckSeed
  # What was raised before is listed back this far.
  RAISED_WITHIN = 60.days
  RAISED_LIMIT = 30
  CANNOT_REACH = "When what this check looks at is outside that, say so plainly, such as \"I can't reach production for this check\", " \
                 "and do not try to read it.".freeze

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
        "today" => Time.current.in_time_zone(@check.zone).to_date.iso8601, "runs_within" => runs_within
      }.compact,
      "already_raised" => raised,
      "billing" => (billing if @check.kind == Investigation::Check::KIND_COST)
    }.compact
  end

  private

  # The check runs in its owner's name, so it reads only what they may. Said up front, so a run names what it could not
  # reach rather than reading around it.
  def runs_within
    owner = @check.owner
    return "This check has no owner, so it reaches nothing. #{CANNOT_REACH}" unless owner

    environments = ResourceMap::Resource.environments_visible_to(owner, @investigation.workspace)
    where = if environments.nil? then "every environment on the map"
    elsif environments.empty? then "no environment on the map"
    else @investigation.workspace.catalog_entries.where(id: environments).order(:name).pluck(:name).to_sentence
    end
    "This check runs in #{owner.display_name}'s name, so it reads only what they may, on the map #{where}. #{CANNOT_REACH}"
  end

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

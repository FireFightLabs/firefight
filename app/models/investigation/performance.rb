# How Halon has done for one workspace over a window: how often it answered, how fast, what the team said of its
# answers, what came of its fixes, and where it was wrong. Read from what the team recorded, never estimated. Rehearsals
# are measurement, not Halon at work, so they are left out.
class Investigation::Performance
  WINDOWS = [ 7, 30, 90 ].freeze
  DEFAULT_WINDOW = 30
  NOT_RATED = "not_rated".freeze
  MISTAKES_SHOWN = 10

  Week = Data.define(:starts_on, :confirmed, :partial, :wrong, :not_rated)
  Fixes = Data.define(:proposed, :applied, :undone, :cancelled)
  Mistake = Data.define(:finding, :lessons)

  attr_reader :days

  def initialize(workspace, days: DEFAULT_WINDOW)
    @workspace = workspace
    @days = WINDOWS.include?(days.to_i) ? days.to_i : DEFAULT_WINDOW
  end

  def since = @since ||= days.days.ago.beginning_of_day

  def runs_count = runs.count

  def answered_count = answered.count

  def ended_count = runs.where.not(status: Investigation::LIVE_STATUSES).count

  def median_seconds
    @median_seconds ||= answered.where.not(started_at: nil, completed_at: nil)
                                .pick(Arel.sql("percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM investigations.completed_at - investigations.started_at))"))
                                &.round
  end

  # What the team said of the answers, each outcome counted once.
  def verdicts
    @verdicts ||= begin
      counts = answered.group("investigation_findings.outcome").count
      Investigation::Finding::OUTCOMES.index_with { |outcome| counts[outcome].to_i }.merge(NOT_RATED => counts[nil].to_i)
    end
  end

  def rated_count = verdicts.except(NOT_RATED).values.sum

  def weeks
    counts = answered.group(Arel.sql("date_trunc('week', investigations.created_at)::date"), "investigation_findings.outcome").count
    first = since.to_date.beginning_of_week
    (first..Date.current).step(7).map do |starts_on|
      count = ->(outcome) { counts[[ starts_on, outcome ]].to_i }
      Week.new(starts_on: starts_on, confirmed: count.(Investigation::Finding::OUTCOME_CONFIRMED), partial: count.(Investigation::Finding::OUTCOME_PARTIAL),
               wrong: count.(Investigation::Finding::OUTCOME_WRONG), not_rated: count.(nil))
    end
  end

  # A fix counts once, as undone when its undo went through, otherwise by how it ended.
  def fixes = @fixes ||= count_fixes

  # The answers the team marked wrong, newest first, each with what Halon learned from its incident.
  def mistakes
    findings = Investigation::Finding.where(id: answered.select("investigation_findings.id"), outcome: Investigation::Finding::OUTCOME_WRONG)
                                     .includes(:winning_hypothesis, investigation: :subject).order(outcome_at: :desc).limit(MISTAKES_SHOWN).to_a
    incidents = findings.filter_map { |finding| finding.investigation.incident }
    lessons = Chat::Memory.in_use.where(workspace: @workspace, source: incidents).order(:created_at).group_by(&:source_id)
    findings.map { |finding| Mistake.new(finding: finding, lessons: lessons.fetch(finding.investigation.incident&.id, [])) }
  end

  private

  def count_fixes
    plans = Investigation::RemediationPlan.where(undoes_id: nil, finding_id: answered.select("investigation_findings.id"))
    undone = Investigation::RemediationPlan.where(undoes_id: plans.select(:id), status: [ Investigation::RemediationPlan::STATUS_APPLIED, Investigation::RemediationPlan::STATUS_PARTLY_APPLIED ]).select(:undoes_id)
    by_status = plans.where.not(id: undone).group(:status).count
    Fixes.new(
      proposed: plans.count,
      applied: by_status.values_at(Investigation::RemediationPlan::STATUS_APPLIED, Investigation::RemediationPlan::STATUS_PARTLY_APPLIED).compact.sum,
      undone: plans.where(id: undone).count,
      cancelled: by_status[Investigation::RemediationPlan::STATUS_CANCELLED].to_i
    )
  end

  def runs = @workspace.investigations.seen.where(created_at: since..)

  # A run writes its finding before it ends, so only a run that has ended counts as answered.
  def answered = runs.where.not(status: Investigation::LIVE_STATUSES).joins(:finding).where.not(investigation_findings: { summary: [ nil, "" ] })
end

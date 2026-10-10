# What Halon does on its own once a run an alert started has answered, when the team set unattended rules ahead. A fix
# whose every change is one a rule allows, with each rule's metric above its threshold in a fresh reading, is applied by
# Halon at once, its steps running as Halon through the gateway. The incident is told either way once a rule touched the
# fix: what Halon did and how to undo it, or why it did not act and that the fix waits for someone.
class Investigation::Unattended
  # What the incident is told. acted says whether Halon applied the fix. rules are the ones that covered it, readings
  # what Halon read for each, and reason why it did not act when it did not.
  Note = Data.define(:plan, :acted, :rules, :readings, :reason) do
    def initialize(readings: [], reason: nil, **) = super
  end

  WAITS = "The fix waits for someone to apply it.".freeze
  COULD_NOT_CHECK = "Firefight could not check the rule just now.".freeze

  def self.consider!(investigation)
    plan = investigation.finding&.remediation_plan
    return unless investigation.started_by_alert? && !investigation.rehearsal? && plan
    return unless plan.status == Investigation::RemediationPlan::STATUS_PROPOSED && plan.appliable?
    return unless plan.claim_unattended_check!

    new(plan).consider!
  end

  def initialize(plan)
    @plan = plan
    @investigation = plan.finding.investigation
    @workspace = @investigation.workspace
  end

  def consider!
    changes = @plan.steps.select { |step| step.runs_itself?(@workspace) }
    covering = changes.to_h { |step| [ step, Ability::UnattendedRule.covering(@workspace, step) ] }
    rules = covering.values.compact.uniq
    # No rule touches this fix, so nothing changes from a fix anyone would apply by hand, and nothing is said.
    return if rules.empty?

    uncovered = covering.find { |_step, rule| rule.nil? }&.first
    return tell(rules, reason: "Step #{uncovered.position} (#{uncovered.description.delete_suffix('.')}) is not a change any rule allows.") if uncovered

    blocked = rules.find(&:blocked_reason)
    return tell(rules, reason: blocked.blocked_reason) if blocked

    readings = rules.map { |rule| rule.read!(incident: @investigation.incident) }
    low = readings.reject(&:above?)
    return tell(rules, readings: readings.map(&:words), reason: low.map(&:words).join(" ")) if low.any?

    act!(covering, rules, readings)
  rescue Ability::UnattendedRule::Reading::Unread => error
    tell(rules, reason: error.message)
  rescue StandardError => error
    # The look is claimed, so a retry would never come back to it. Whoever reads the incident is told instead.
    Rails.logger.error({ event: "unattended.check_failed", plan_id: @plan.id, error: error.class.name }.to_json)
    tell(rules, reason: COULD_NOT_CHECK) if rules.present?
  end

  private

  def act!(covering, rules, readings)
    words = readings.map(&:words)
    said = rules.zip(words).map { |rule, reading| "#{rule.sentence} #{reading}" }.join("\n")
    return unless @plan.apply_unattended!(rules: covering, reading: said)

    InvestigationFixJob.perform_later(@plan.id)
    post(Note.new(plan: @plan, acted: true, rules: rules, readings: words))
  end

  def tell(rules, reason:, readings: [])
    post(Note.new(plan: @plan, acted: false, rules: rules, readings: readings, reason: reason))
  end

  # Acting is said in the channel, where whoever is paged looks first. Not acting is said under the run's answer.
  def post(note)
    channel_id = @investigation.channel_id
    return if channel_id.blank?

    WorkspaceAdapter.for(@workspace).post_unattended_note(channel_id: channel_id, thread_id: (@investigation.thread_id unless note.acted), note: note)
  rescue AdapterError => error
    Rails.logger.warn({ event: "unattended.note_not_posted", plan_id: @plan.id, error: error.class.name }.to_json)
  end
end

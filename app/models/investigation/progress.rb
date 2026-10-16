# A run as a short checklist people follow from the channel: what Halon looked at, grouped by the kind of system it
# read, then the answer. Read from the run's own steps each time, so a resumed run, a redraw after a restart and the
# last word all say the same thing. The platform decides how it looks.
class Investigation::Progress
  PENDING = "pending".freeze
  RUNNING = "running".freeze
  DONE = "done".freeze
  FAILED = "failed".freeze

  Task = Data.define(:key, :title, :status, :detail)

  # A channel reads a handful of lines at a glance, so the kinds past this many are counted together as other checks.
  GROUP_LIMIT = 5
  DETAIL_LIMIT = 150

  KNOWN = "known".freeze
  DEPLOYS = "deploys".freeze
  OBSERVABILITY = "observability".freeze
  CODE = "code".freeze
  DATABASES = "databases".freeze
  CLOUD = "cloud".freeze
  NOTES = "notes".freeze
  ALERTS = "alerts".freeze
  MAP = "map".freeze
  BROWSER = "browser".freeze
  OTHER = "other".freeze
  ANSWER = "answer".freeze

  TITLES = {
    KNOWN => "Gathered what Firefight knows", DEPLOYS => "Checked recent deploys", OBSERVABILITY => "Read the logs and metrics",
    CODE => "Read the code", DATABASES => "Checked the database", CLOUD => "Checked cloud resources", NOTES => "Read the team's notes",
    ALERTS => "Checked alerts and on-call", MAP => "Checked the resource map", BROWSER => "Checked the page in a browser", OTHER => "Ran other checks"
  }.freeze

  # Each kind of question a provider's tools answer (IntegrationProvider.specialist_for), as the group its reads join, so
  # a connection is placed by what its provider declares and nothing here names one.
  SPECIALIST_GROUPS = {
    IntegrationProvider::SPECIALIST_CODE => CODE, IntegrationProvider::SPECIALIST_DEPLOYS => DEPLOYS,
    IntegrationProvider::SPECIALIST_OBSERVABILITY => OBSERVABILITY, IntegrationProvider::SPECIALIST_DATABASES => DATABASES,
    IntegrationProvider::SPECIALIST_CLOUD => CLOUD, IntegrationProvider::SPECIALIST_TICKETS => NOTES,
    IntegrationProvider::SPECIALIST_ON_CALL => ALERTS
  }.freeze

  # Firefight's own reads, by the resource their action is on.
  RESOURCE_GROUPS = {
    Ability::Action::RESOURCE_MAP => MAP, Ability::Action::RESOURCE_INCIDENTS => ALERTS, Ability::Action::RESOURCE_ALERTS => ALERTS,
    Ability::Action::RESOURCE_CATALOG => MAP, Ability::Action::RESOURCE_RUNBOOKS => NOTES, Ability::Action::RESOURCE_HANDBOOK => NOTES,
    Ability::Action::RESOURCE_MEMORY => NOTES, Ability::Action::RESOURCE_INCIDENT_TRANSCRIPTS => ALERTS,
    Ability::Action::RESOURCE_BROWSER => BROWSER, Ability::Action::RESOURCE_SANDBOX => CODE
  }.freeze

  # The capabilities and Firefight's own tools that read one kind of system whichever connection answers them.
  def self.tool_groups
    @tool_groups ||= {
      Integrations::Capabilities.spec(Integrations::Capabilities::LOGS).tool_name => OBSERVABILITY,
      Integrations::Capabilities.spec(Integrations::Capabilities::METRICS).tool_name => OBSERVABILITY,
      Integrations::Capabilities.spec(Integrations::Capabilities::ERRORS).tool_name => OBSERVABILITY,
      Integrations::Capabilities.spec(Integrations::Capabilities::TRACES).tool_name => OBSERVABILITY,
      Integrations::Capabilities.spec(Integrations::Capabilities::STATUS).tool_name => OBSERVABILITY,
      Integrations::Capabilities::KEY_QUERY_TOOL => OBSERVABILITY,
      Integrations::Capabilities::LOG_PATTERNS_TOOL => OBSERVABILITY,
      Integrations::Capabilities.spec(Integrations::Capabilities::DEPLOYS).tool_name => DEPLOYS,
      Integrations::Capabilities.spec(Integrations::Capabilities::HISTORY).tool_name => DEPLOYS,
      ResourceMap::Timeline::TOOL_NAME => DEPLOYS,
      Chat::BrowserCheck::TOOL_NAME => BROWSER
    }.freeze
  end

  attr_reader :investigation

  # stop_reason is the plain sentence a run that ended without an answer stopped with.
  def initialize(investigation, stop_reason: nil)
    @investigation = investigation
    @stop_reason = stop_reason
  end

  def finding = @investigation.finding

  def answered? = finding.present?

  def stopped? = !answered? && @stop_reason.present?

  def finished? = answered? || stopped?

  def tasks
    @tasks ||= [ Task.new(key: KNOWN, title: TITLES.fetch(KNOWN), status: DONE, detail: nil), *group_tasks, answer_task ]
  end

  # What changes when the checklist does, so a redraw that would say the same thing is never sent.
  def signature = tasks.map { |task| task.to_h.values.join("|") }.join("\n")

  private

  def answer_task
    return Task.new(key: ANSWER, title: finding.headline, status: DONE, detail: finding.what_is_wrong_line.truncate(DETAIL_LIMIT).presence) if answered?
    return Task.new(key: ANSWER, title: "Stopped without an answer", status: FAILED, detail: @stop_reason.to_s.truncate(DETAIL_LIMIT)) if stopped?

    Task.new(key: ANSWER, title: "Find the cause", status: PENDING, detail: nil)
  end

  def group_tasks
    grouped = steps.group_by { |step| group_of(step) }
    grouped.delete(nil)
    keys = grouped.keys
    if keys.size > GROUP_LIMIT
      kept = keys.first(GROUP_LIMIT - 1)
      rest = (keys - kept).flat_map { |key| grouped.delete(key) }
      grouped = grouped.slice(*kept).merge(OTHER => [ *grouped[OTHER], *rest ])
    end
    grouped.map { |key, members| group_task(key, members) }
  end

  def group_task(key, members)
    running = members.any? { |step| step.status == Investigation::Step::STATUS_RUNNING || step.status == Investigation::Step::STATUS_PENDING }
    failed = members.count { |step| failed?(step) }
    status = if running then RUNNING
    elsif failed == members.size then FAILED
    else DONE
    end
    detail = "#{failed} of #{members.size} #{'lookup'.pluralize(members.size)} failed" if failed.positive? && !running
    Task.new(key: key, title: TITLES.fetch(key), status: status, detail: detail)
  end

  # A provider's not found is an answer to the check, never a failure of it.
  def failed?(step)
    step.status == Investigation::Step::STATUS_FAILED && step.failure_kind != Chat::StepOutcome::FAILURE_NOT_FOUND
  end

  def steps = @steps ||= @investigation.steps.ordered.to_a

  def group_of(step)
    name = step.tool_name.to_s
    return nil if name.empty?

    self.class.tool_groups[name] || RESOURCE_GROUPS[prefix(step)] || SPECIALIST_GROUPS[specialists[prefix(step)]] || OTHER
  end

  def prefix(step) = step.action_key.to_s.split(".").first

  # Each connection the steps went through, by its slug, with the kind of question its provider answers.
  def specialists
    @specialists ||= begin
      slugs = steps.map { |step| prefix(step) }.uniq - RESOURCE_GROUPS.keys
      @investigation.workspace.integrations.where(slug: slugs).pluck(:slug, :provider)
                    .to_h { |slug, provider| [ slug, IntegrationProvider.specialist_for(provider) ] }
    end
  end
end

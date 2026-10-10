# What changed around one resource, one service or the whole workspace over a window, from every source Firefight
# holds, as one list newest first: what sweeps and live updates saw change on the map (deploys, settings, status), what
# a provider said changed between sweeps, such as an edit made by hand, the changes people and agents made through
# Firefight (the activity log, for those who may read it), and the runs a caller read live from the provider that runs
# each resource (Integrations::Capabilities::HISTORY), passed in as entries. Each entry links to the page it came from
# where there is one, and what the list could not cover is said in notes, never left out quietly.
class ResourceMap::Timeline
  TOOL_NAME = "what_changed".freeze
  DEFAULT_MINUTES = 24 * 60
  MAX_MINUTES = 30 * 24 * 60
  # The most resources a caller reads runs for live, so a service of many parts is not a page of provider calls.
  LIVE_AT_MOST = 5
  # What a resource's panel on the map shows, the week a provider's reports are kept for.
  PANEL_WINDOW = 7.days
  RESOURCE_ARG = "resource".freeze
  SERVICE_ARG = "service".freeze
  SHOWN = 80
  # A provider reporting the same thing again within this is one change, such as a rollout's many updates.
  BURST = 2.minutes
  # The newest reports read, since a busy cluster can report thousands in a day.
  EVENTS_READ = 2_000
  # A change through Firefight this long before a provider reported one is taken as its cause.
  CAUSED_WITHIN = 5.minutes
  HAND_EDIT = "and nothing in Firefight's activity log matches it, so it was made at the provider directly, such as by hand or by another tool".freeze

  SUBJECT_RESOURCE = "resource".freeze
  SUBJECT_SERVICE = "service".freeze
  SUBJECT_WORKSPACE = "workspace".freeze

  KIND_DEPLOY = "deploy".freeze
  KIND_CONFIG = "config".freeze
  KIND_STATUS = "status".freeze
  KIND_APPEARED = "appeared".freeze
  KIND_REMOVED = "removed".freeze
  KIND_RENAMED = "renamed".freeze
  # A provider said something changed between sweeps.
  KIND_REPORTED = "reported".freeze
  # A run read live from the provider, such as a CI run, a build or a deploy.
  KIND_RUN = "run".freeze
  # A change made through Firefight.
  KIND_FIREFIGHT = "firefight".freeze
  KINDS = [ KIND_DEPLOY, KIND_CONFIG, KIND_STATUS, KIND_APPEARED, KIND_REMOVED, KIND_RENAMED, KIND_REPORTED, KIND_RUN, KIND_FIREFIGHT ].freeze
  KIND_LABELS = {
    KIND_DEPLOY => "Deploy", KIND_CONFIG => "Setting", KIND_STATUS => "Status", KIND_APPEARED => "Appeared", KIND_REMOVED => "Removed",
    KIND_RENAMED => "Renamed", KIND_REPORTED => "Reported change", KIND_RUN => "Run", KIND_FIREFIGHT => "Through Firefight"
  }.freeze

  # Seen on the map by a sweep or a live update.
  SOURCE_MAP = "map".freeze
  # Said by the provider between sweeps.
  SOURCE_LIVE_UPDATE = "live_update".freeze
  # Read from the provider for this list.
  SOURCE_PROVIDER = "provider".freeze
  # The activity log.
  SOURCE_FIREFIGHT = "firefight".freeze
  SOURCES = [ SOURCE_MAP, SOURCE_LIVE_UPDATE, SOURCE_PROVIDER, SOURCE_FIREFIGHT ].freeze

  CHANGE_KINDS = {
    ResourceMap::Change::KIND_DEPLOYED => KIND_DEPLOY, ResourceMap::Change::KIND_CONFIGURED => KIND_CONFIG,
    ResourceMap::Change::KIND_STATUS_CHANGED => KIND_STATUS, ResourceMap::Change::KIND_APPEARED => KIND_APPEARED,
    ResourceMap::Change::KIND_REMOVED => KIND_REMOVED, ResourceMap::Change::KIND_RENAMED => KIND_RENAMED
  }.freeze
  REPORTED_WORDS = {
    ResourceMap::Event::ADDED => "added", ResourceMap::Event::UPDATED => "changed", ResourceMap::Event::REMOVED => "removed",
    ResourceMap::Event::LINKED => "linked to something else", ResourceMap::Event::RESCOPE => "reaching different things"
  }.freeze

  # where is the resource or connection it happened on, by the name a person knows it by, and by who did it when that is
  # known. link is the page it came from.
  Entry = Data.define(:at, :kind, :source, :what, :where, :by, :link, :resource_id) do
    def initialize(where: nil, by: nil, link: nil, resource_id: nil, **) = super

    def to_h
      { at: at.utc.iso8601, kind: kind, source: source, what: what, where: where, by: by, link: link, resource_id: resource_id }.compact
    end

    def line
      who = by ? " by #{by}" : ""
      "- #{at.utc.iso8601} #{KIND_LABELS.fetch(kind)}: #{what}#{who}#{" #{link}" if link}"
    end
  end

  # The list is about a resource, a catalog service and the resources that run it, or the whole workspace.
  Subject = Data.define(:kind, :name, :resources, :entry) do
    def initialize(entry: nil, **) = super

    def described
      case kind
      when SUBJECT_RESOURCE then name
      when SUBJECT_SERVICE then "#{name} (service)"
      else "the workspace"
      end
    end
  end

  DESCRIPTION = "What changed, everywhere, over a window, newest first in one list: deploys and builds, CI and release runs read " \
                "live from the provider that runs each resource, settings and status the map saw change, changes a provider " \
                "reported between sweeps (an edit made by hand shows here), and changes made through Firefight, with who made " \
                "them and links to each page. Name a resource on the map, a service from the catalog, or neither for the whole " \
                "workspace. Use it first when asked what changed before something broke".freeze
  SCHEMA = {
    "type" => "object",
    "properties" => {
      RESOURCE_ARG => { "type" => "string", "description" => "A resource on the map, by its name, its provider's id or its id on the map (optional)" },
      SERVICE_ARG => { "type" => "string", "description" => "A service from the catalog, by its name, for every resource that runs it (optional)" },
      "minutes" => { "type" => "integer", "description" => "How far back from now, in minutes (optional, #{DEFAULT_MINUTES}, at most #{MAX_MINUTES})" },
      "start" => { "type" => "string", "description" => "Start of the window as an ISO 8601 time, instead of minutes (optional)" },
      "end" => { "type" => "string", "description" => "End of the window as an ISO 8601 time (optional, now)" }
    },
    "required" => []
  }.freeze

  attr_reader :subject, :from, :to

  # The subject asked for, or a sentence saying why it could not be found.
  def self.subject(workspace, principal, given)
    given = given.to_h.stringify_keys
    visible = ResourceMap::Resource.visible_to(principal, workspace)
    if given[RESOURCE_ARG].present?
      found = ResourceMap::Resource.locate(workspace, principal, given[RESOURCE_ARG])
      return found if found.is_a?(String)

      return Subject.new(kind: SUBJECT_RESOURCE, name: found.scoped_name, resources: [ found ])
    end
    return Subject.new(kind: SUBJECT_WORKSPACE, name: nil, resources: visible.present) if given[SERVICE_ARG].blank?

    entry = service(workspace, given[SERVICE_ARG])
    return "Nothing in the catalog is called #{given[SERVICE_ARG]}. search_catalog finds a service by part of its name." unless entry

    Subject.new(kind: SUBJECT_SERVICE, name: entry.name, entry: entry,
                resources: visible.present.where(id: ResourceMap::EntryLink.where(catalog_entry: entry).select(:resource_id)).order(:name).to_a)
  end

  def self.service(workspace, reference)
    wanted = reference.to_s.strip
    entries = workspace.catalog_entries.active
    entries.find_by(slug: wanted) || entries.where("lower(catalog_entries.name) = ?", wanted.downcase).first
  end

  # The window asked for, as [from, to]. Raises ArgumentError with words a caller can act on.
  def self.window(given, now: Time.current)
    given = given.to_h.stringify_keys
    to = given["end"].present? ? time(given["end"], "end") : now
    from = if given["start"].present?
      time(given["start"], "start")
    else
      minutes = given["minutes"].to_i.positive? ? given["minutes"].to_i : DEFAULT_MINUTES
      to - minutes.minutes
    end
    raise ArgumentError, "start must be before end." unless from < to
    raise ArgumentError, "The window is at most #{MAX_MINUTES / (24 * 60)} days." if to - from > MAX_MINUTES.minutes

    [ from, to ]
  end

  def self.time(value, name)
    Time.zone.iso8601(value.to_s)
  rescue ArgumentError
    raise ArgumentError, "#{name} must be an ISO 8601 time, such as 2026-10-10T09:00:00Z."
  end
  private_class_method :time

  # A run a caller read live, from the run's own fields (Integrations::Capabilities::History::Run#to_h), on the
  # connection it was read through.
  def self.run_entry(resource, run, through:)
    run = run.to_h.stringify_keys
    at = Time.zone.parse(run["started_at"].to_s) || Time.zone.parse(run["finished_at"].to_s)
    return unless at

    named = [ run["number"] ? "##{run['number']}" : run["id"], run["name"] ].compact_blank.join(" ")
    took = run["seconds"] ? ", took #{ActiveSupport::Duration.build(run['seconds'].to_i).inspect}" : ""
    detail = run["detail"].present? ? " (#{run['detail']})" : ""
    Entry.new(at: at, kind: KIND_RUN, source: SOURCE_PROVIDER, what: "#{resource.scoped_name} run #{named} #{run['status']}#{took}#{detail}, from #{through}",
              where: resource.scoped_name, link: run["url"].presence, resource_id: resource.id)
  end

  def initialize(workspace:, principal:, subject:, from:, to:)
    @workspace = workspace
    @principal = principal
    @subject = subject
    @from = from
    @to = to
  end

  # The resources a caller reads runs for live, those of one resource or service and never the whole workspace.
  def live_targets
    return [] if @subject.kind == SUBJECT_WORKSPACE

    @subject.resources.to_a.select { |resource| resource.removed_at.nil? }.first(LIVE_AT_MOST)
  end

  # Every entry, newest first, with the runs a caller read live.
  def entries(live: [])
    (map_changes + reported + firefight + live.compact).select { |entry| entry.at.between?(@from, @to) }.sort_by(&:at).reverse.first(SHOWN)
  end

  # What the list could not cover, each a sentence. read are notes from the caller's live reads, such as a provider that
  # could not be asked.
  def notes(read: [])
    [ *read, *swept_only, *flags, activity_note, live_note, kept_note ].compact
  end

  def text(live: [], read: [])
    listed = entries(live: live)
    window = "from #{@from.utc.iso8601} to #{@to.utc.iso8601}"
    head = listed.empty? ? "Nothing Firefight holds changed for #{@subject.described} #{window}." : "What changed for #{@subject.described} #{window}, newest first:"
    more = listed.size == SHOWN ? "Only the newest #{SHOWN} are shown. Narrow the window for the rest." : nil
    covered = notes(read: read)
    [ head, *listed.map(&:line), more, ("Not in this list:\n#{covered.map { |note| "- #{note}" }.join("\n")}" if covered.any?) ].compact.join("\n")
  end

  def to_h(live: [], read: [])
    { subject: @subject.described, from: @from.utc.iso8601, to: @to.utc.iso8601, changes: entries(live: live).map(&:to_h), not_covered: notes(read: read) }
  end

  private

  def resource_ids
    @resource_ids ||= @subject.kind == SUBJECT_WORKSPACE ? @subject.resources.select(:id) : @subject.resources.map(&:id)
  end

  def map_changes
    ResourceMap::Change.where(workspace: @workspace, resource_id: resource_ids, happened_at: @from..@to).includes(:resource).newest_first.limit(SHOWN).map do |change|
      resource = change.resource
      Entry.new(at: change.happened_at, kind: CHANGE_KINDS.fetch(change.kind), source: SOURCE_MAP, what: change.words, where: resource.scoped_name,
                link: resource.url.presence, resource_id: resource.id)
    end
  end

  # The connections behind the subject's resources, or every one in the workspace for the whole workspace.
  def rows
    @rows ||= if @subject.kind == SUBJECT_WORKSPACE
      IntegrationEnvironment.reachable.includes(:integration).where(integrations: { workspace_id: @workspace.id }).to_a
    else
      @subject.resources.flat_map(&:holders).uniq(&:id)
    end
  end

  # What providers said changed between sweeps, a burst about the same thing read as one. Only what names a resource
  # the reader may see on the map, and for one resource or service only what names one of its resources.
  def reported
    visible = ResourceMap::Resource.visible_to(@principal, @workspace)
    events = ResourceMap::ReceivedEvent.where(integration_environment_id: rows.map(&:id), happened_at: @from..@to)
                                       .where.not(action: ResourceMap::Event::RESCOPE).order(happened_at: :desc).limit(EVENTS_READ).to_a.reverse
    by_row = rows.index_by(&:id)
    named = events.filter_map do |event|
      scope = event.scope_read
      next if scope.external_id.nil?

      row = by_row[event.integration_environment_id]
      resource = resource_for(row, scope, visible)
      [ event, row, resource ] if resource
    end
    bursts(named).map { |burst| reported_entry(burst) }
  end

  def resource_for(row, scope, visible)
    @resources_by_scope ||= {}
    @resources_by_scope[[ row.id, scope.to_h ]] ||= begin
      candidates = @subject.kind == SUBJECT_WORKSPACE ? visible.present.where(external_id: scope.external_id).to_a : @subject.resources
      candidates.find { |resource| scope.covers?(resource.key) && resource.holders.any? { |holder| holder.id == row.id } } || false
    end
    @resources_by_scope[[ row.id, scope.to_h ]] || nil
  end

  def bursts(named)
    named.chunk_while do |(before, before_row, before_resource), (after, after_row, after_resource)|
      before_row.id == after_row.id && before_resource.id == after_resource.id && before.action == after.action && after.happened_at - before.happened_at <= BURST
    end.to_a
  end

  def reported_entry(burst)
    first, row, resource = burst.first
    last = burst.last.first
    times = burst.size > 1 ? " #{burst.size} times up to #{last.happened_at.utc.iso8601}" : ""
    cause = activity_readable? && !caused_through_firefight?(row, first.happened_at) ? ", #{HAND_EDIT}" : ""
    Entry.new(at: first.happened_at, kind: KIND_REPORTED, source: SOURCE_LIVE_UPDATE,
              what: "#{row.integration.display_name} reported #{resource.scoped_name} #{REPORTED_WORDS.fetch(first.action)}#{times}#{cause}",
              where: resource.scoped_name, link: resource.url.presence, resource_id: resource.id)
  end

  # A change through Firefight on the same connection shortly before.
  def caused_through_firefight?(row, at)
    keys = tool_keys_by_integration.fetch(row.integration_id, [])
    keys.any? && changes_through_firefight.any? { |invocation| keys.include?(invocation.action_key) && invocation.created_at.between?(at - CAUSED_WITHIN, at + 1.minute) }
  end

  def tool_keys_by_integration
    @tool_keys_by_integration ||= Integration::Tool.where(integration_id: rows.map(&:integration_id).uniq).group_by(&:integration_id)
                                                  .transform_values { |tools| tools.map(&:action_key) }
  end

  # The activity log is for those who may read it, an admin by default.
  def activity_readable?
    return @activity_readable if defined?(@activity_readable)

    @activity_readable = @principal.present? && @principal.may?(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_READ, @workspace)
  end

  def changes_through_firefight
    @changes_through_firefight ||= Ability::Invocation.where(workspace: @workspace, decision: Ability::Invocation::DECISION_ALLOW,
                                                             outcome: Ability::Invocation::OUTCOME_SUCCESS, created_at: (@from - CAUSED_WITHIN)..@to)
                                                      .where.not(risk_level: Ability::Action::RISK_READ).order(created_at: :desc).limit(SHOWN).to_a
  end

  # Changes made through Firefight, on the subject's connections and naming one of its resources, or every one for the
  # whole workspace, Firefight's own settings included.
  def firefight
    return [] unless activity_readable?

    found = changes_through_firefight.select { |invocation| invocation.created_at.between?(@from, @to) }
    found = found.select { |invocation| about_subject?(invocation) } unless @subject.kind == SUBJECT_WORKSPACE
    link = AppUrl.absolute(Rails.application.routes.url_helpers.gateway_activity_path)
    Ability::Invocation.with_connection_names(found).map do |invocation|
      Entry.new(at: invocation.created_at, kind: KIND_FIREFIGHT, source: SOURCE_FIREFIGHT, what: firefight_words(invocation),
                where: invocation.connection_name, by: invocation.principal_label, link: link)
    end
  end

  def about_subject?(invocation)
    @subject_keys ||= rows.flat_map { |row| tool_keys_by_integration.fetch(row.integration_id, []) }.to_set
    return false unless @subject_keys.include?(invocation.action_key)

    said = invocation.params.to_json.downcase
    @subject.resources.any? { |resource| said.include?(resource.external_id.to_s.downcase) || said.include?(resource.name.to_s.downcase) }
  end

  def firefight_words(invocation)
    through = Ability::Source.label(invocation.source)
    via = through ? ", from #{through}" : ""
    if invocation.connection_name
      tool = invocation.action_key.split(".").last.to_s.tr("_-", "  ")
      "#{tool.upcase_first} through #{invocation.connection_name}#{via}"
    else
      resource, action = invocation.action_key.split(".", 2)
      "#{Ability::Action.label(resource)}: #{action.to_s.humanize(capitalize: false)}#{via}"
    end
  end

  # Connections whose provider cannot say what changed, or whose live updates are off, are read at each hourly sweep.
  def swept_only
    rows.uniq(&:integration_id).filter_map do |row|
      state = row.live_updates
      next if state&.on

      "#{row.integration.display_name} is read at the hourly sweep#{state ? ' while its live updates are off' : ''}, so a change there in the last hour may not be here yet."
    end
  end

  def flags
    @workspace.integrations.active.select { |integration| IntegrationProvider.find(integration.provider)&.holds_flags }.map do |integration|
      "Feature flag changes are kept at #{integration.display_name}, and this list does not read them. Its own tools and its feature flags skill do."
    end
  end

  def activity_note
    "Changes made through Firefight are left out, since only those who may read the activity log see them." unless activity_readable?
  end

  def live_note
    "Runs are read live only for one resource or service. Name one to see its deploys and runs as the provider has them." if @subject.kind == SUBJECT_WORKSPACE
  end

  def kept_note
    kept = ResourceMap::ReceivedEvent::KEPT_FOR
    "What providers reported between sweeps is kept for #{kept.inspect}, so earlier reports are not here." if @from < kept.ago - 1.hour
  end
end

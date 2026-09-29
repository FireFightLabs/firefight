# What runs where, synced from each connection by machines. The catalog is curated by people and routes alerts, the map
# is read off the providers themselves, so the two never share a table. A resource carries its provider, account and the
# connection that saw it, so several clouds sit in one map.
module ResourceMap
  KIND_SERVICE = "service".freeze
  KIND_BUILD_SERVICE = "build_service".freeze
  KIND_JOB = "job".freeze
  KIND_DATABASE = "database".freeze
  KIND_BRANCH = "branch".freeze
  KIND_REPOSITORY = "repository".freeze
  KIND_DOMAIN = "domain".freeze
  KINDS = [ KIND_SERVICE, KIND_BUILD_SERVICE, KIND_JOB, KIND_DATABASE, KIND_BRANCH, KIND_REPOSITORY, KIND_DOMAIN ].freeze

  # Read as "from runs builds of to", "from is built from to", and so on. From always depends on to, so what fails with a
  # resource is everything with a link into it.
  RELATION_RUNS_BUILDS_OF = "runs_builds_of".freeze
  RELATION_BUILT_FROM = "built_from".freeze
  RELATION_SERVED_BY = "served_by".freeze
  RELATION_BRANCH_OF = "branch_of".freeze
  RELATION_USES = "uses".freeze
  RELATIONS = [ RELATION_RUNS_BUILDS_OF, RELATION_BUILT_FROM, RELATION_SERVED_BY, RELATION_BRANCH_OF, RELATION_USES ].freeze
  RELATION_WORDS = {
    RELATION_RUNS_BUILDS_OF => "runs builds of", RELATION_BUILT_FROM => "is built from", RELATION_SERVED_BY => "is served by",
    RELATION_BRANCH_OF => "is a branch of", RELATION_USES => "uses"
  }.freeze

  # Providers that put things on the map without being a connection of their own, such as a domain a service serves.
  PROVIDER_NAMES = { "dns" => "Domains" }.freeze

  def self.provider_name(key) = IntegrationProvider.find(key)&.name || PROVIDER_NAMES.fetch(key, key.to_s.humanize)

  # How a link was found. Declared and matched come from sweeps and are replaced by the next one. Added by a person and
  # suggested by Halon are kept until someone removes them, and a suggestion is not a fact until it is confirmed.
  ORIGIN_DECLARED = "declared".freeze
  ORIGIN_MATCHED = "matched".freeze
  ORIGIN_PERSON = "person".freeze
  ORIGIN_SUGGESTED = "suggested".freeze
  ORIGINS = [ ORIGIN_DECLARED, ORIGIN_MATCHED, ORIGIN_PERSON, ORIGIN_SUGGESTED ].freeze
  SWEPT_ORIGINS = [ ORIGIN_DECLARED, ORIGIN_MATCHED ].freeze

  # What one sweep of one connection saw. A resource is named by its key, the same whichever connection reports it, so a
  # repository two services build from is one resource. gaps are the parts the sweep could not read, in words.
  Snapshot = Data.define(:resources, :links, :gaps) do
    def initialize(resources:, links: [], gaps: []) = super
  end

  Found = Data.define(:provider, :account, :kind, :external_id, :name, :status, :url, :details) do
    def initialize(status: nil, url: nil, details: {}, **) = super

    def key = [ provider, account, kind, external_id ]
  end

  FoundLink = Data.define(:from, :to, :relation)

  # Writes a sweep. Everything the connection reported is upserted and seen now, what it reported before and no longer
  # does is marked removed, and its declared and matched links are replaced. A person's links and Halon's suggestions stay.
  def self.record!(environment_row, snapshot, at: Time.current)
    workspace_id = environment_row.integration.workspace_id

    ActiveRecord::Base.transaction do
      # One sweep of a connection at a time, so the hourly run and a Sync now cannot interleave their writes.
      environment_row.lock!
      ids = snapshot.resources.uniq(&:key).to_h { |found| [ found.key, upsert_resource(workspace_id, environment_row, found, at) ] }
      gone = Resource.where(integration_environment_id: environment_row.id, removed_at: nil).where.not(id: ids.values)
      gone.pluck(:id).each { |id| Change.create!(workspace_id: workspace_id, resource_id: id, kind: Change::KIND_REMOVED, happened_at: at) }
      gone.update_all(removed_at: at, updated_at: at)

      Link.where(integration_environment_id: environment_row.id, origin: SWEPT_ORIGINS).delete_all
      snapshot.links.each do |found|
        from, to = ids.values_at(found.from, found.to)
        next unless from && to

        Link.create!(workspace_id: workspace_id, from_resource_id: from, to_resource_id: to, relation: found.relation,
                     origin: ORIGIN_DECLARED, integration_environment: environment_row, last_seen_at: at)
      end
      environment_row.update!(map_swept_at: at, map_error: nil, map_gaps: snapshot.gaps)
    end
  end

  # A new commit on a service is a deploy, since a sweep only sees the commit that is running.
  DEPLOYED_COMMIT = "deployed_commit".freeze
  SHORT_COMMIT = 7

  # What a provider reported about a resource, named for a person, in the order a person reads it. Other details stay
  # for Halon and are not shown.
  DETAIL_LABELS = {
    "type" => "Type", "plan" => "Plan", "instances" => "Instances", "engine" => "Engine", "region" => "Region",
    "branch" => "Branch", DEPLOYED_COMMIT => "Running commit", "production" => "Production"
  }.freeze

  def self.facts(details)
    DETAIL_LABELS.filter_map do |key, label|
      value = details[key]
      next if value.nil?

      shown = case value
      when true then "Yes"
      when false then "No"
      else key == DEPLOYED_COMMIT ? value.to_s.first(SHORT_COMMIT) : value.to_s
      end
      [ label, shown ]
    end
  end

  def self.upsert_resource(workspace_id, environment_row, found, at)
    identity = { workspace_id: workspace_id, provider: found.provider, account: found.account, kind: found.kind, external_id: found.external_id }
    # Two connections can report the same repository at once, so creating it tolerates losing that race.
    resource = Resource.find_by(identity) || Resource.create_or_find_by!(identity) do |fresh|
      fresh.assign_attributes(name: found.name, integration_environment: environment_row, first_seen_at: at, last_seen_at: at)
    end
    changes = resource.previously_new_record? ? [ [ Change::KIND_APPEARED, nil, nil ] ] : changes_of(resource, found)
    resource.update!(integration_environment: environment_row, name: found.name, status: found.status, url: found.url,
                     details: found.details, last_seen_at: at, removed_at: nil)
    changes.each { |kind, from, to| resource.changes_seen.create!(workspace_id: workspace_id, kind: kind, from_value: from, to_value: to, happened_at: at) }
    resource.id
  end
  private_class_method :upsert_resource

  def self.changes_of(resource, found)
    return [ [ Change::KIND_APPEARED, nil, nil ] ] if resource.removed_at

    before = resource.details[DEPLOYED_COMMIT]
    after = found.details[DEPLOYED_COMMIT]
    [
      ([ Change::KIND_DEPLOYED, before, after ] if after.present? && before != after),
      ([ Change::KIND_STATUS_CHANGED, resource.status, found.status ] if resource.status != found.status && found.status.present?)
    ].compact
  end
  private_class_method :changes_of
end

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
  # What an edge network holds: a zone, the code and sites it runs at the edge, where they keep data, and what sits in
  # front of an origin.
  KIND_ZONE = "zone".freeze
  KIND_WORKER = "worker".freeze
  KIND_SITE = "site".freeze
  KIND_BUCKET = "bucket".freeze
  KIND_KV_NAMESPACE = "kv_namespace".freeze
  KIND_QUEUE = "queue".freeze
  KIND_DATABASE_PROXY = "database_proxy".freeze
  KIND_TUNNEL = "tunnel".freeze
  KIND_LOAD_BALANCER = "load_balancer".freeze
  KIND_ORIGIN_POOL = "origin_pool".freeze
  KIND_ACCESS_APP = "access_app".freeze
  KINDS = [
    KIND_SERVICE, KIND_BUILD_SERVICE, KIND_JOB, KIND_DATABASE, KIND_BRANCH, KIND_REPOSITORY, KIND_DOMAIN, KIND_ZONE, KIND_WORKER,
    KIND_SITE, KIND_BUCKET, KIND_KV_NAMESPACE, KIND_QUEUE, KIND_DATABASE_PROXY, KIND_TUNNEL, KIND_LOAD_BALANCER, KIND_ORIGIN_POOL,
    KIND_ACCESS_APP
  ].freeze

  # Read as "from runs builds of to", "from is built from to", and so on. From always depends on to, so what fails with a
  # resource is everything with a link into it.
  RELATION_RUNS_BUILDS_OF = "runs_builds_of".freeze
  RELATION_BUILT_FROM = "built_from".freeze
  RELATION_SERVED_BY = "served_by".freeze
  RELATION_BRANCH_OF = "branch_of".freeze
  RELATION_USES = "uses".freeze
  RELATION_PART_OF = "part_of".freeze
  RELATION_PROTECTED_BY = "protected_by".freeze
  RELATIONS = [
    RELATION_RUNS_BUILDS_OF, RELATION_BUILT_FROM, RELATION_SERVED_BY, RELATION_BRANCH_OF, RELATION_USES, RELATION_PART_OF,
    RELATION_PROTECTED_BY
  ].freeze
  RELATION_WORDS = {
    RELATION_RUNS_BUILDS_OF => "runs builds of", RELATION_BUILT_FROM => "is built from", RELATION_SERVED_BY => "is served by",
    RELATION_BRANCH_OF => "is a branch of", RELATION_USES => "uses", RELATION_PART_OF => "is part of",
    RELATION_PROTECTED_BY => "is protected by"
  }.freeze

  # Providers that put things on the map without being a connection of their own, such as a domain a service serves.
  DOMAINS = "dns".freeze
  PROVIDER_NAMES = { DOMAINS => "Domains" }.freeze

  # A hostname on the map, whichever connection names it, so the one Cloudflare points at a service and the one that
  # service serves are the same resource.
  def self.domain(host)
    Found.new(provider: DOMAINS, account: host.split(".").last(2).join("."), kind: KIND_DOMAIN, external_id: host, name: host,
              url: "https://#{host}")
  end

  def self.provider_name(key) = IntegrationProvider.find(key)&.name || PROVIDER_NAMES.fetch(key, key.to_s.humanize)

  # The registry's mark and colour, so the map draws a provider the way the Integrations page does. nil for a provider
  # that is not a connection, such as domains.
  def self.provider_entry(key) = IntegrationProvider.find(key)

  # How a link was found. Declared and matched come from sweeps and are replaced by the next one. Added by a person and
  # suggested by Halon are kept until someone removes them, and a suggestion is not a fact until it is confirmed.
  ORIGIN_DECLARED = "declared".freeze
  ORIGIN_MATCHED = "matched".freeze
  ORIGIN_PERSON = "person".freeze
  ORIGIN_SUGGESTED = "suggested".freeze
  # Firefight's own guess from clues every sweep can check, such as a service and a database named for the same
  # project. Like Halon's suggestions, it is not a fact until a person confirms it.
  ORIGIN_INFERRED = "inferred".freeze
  ORIGINS = [ ORIGIN_DECLARED, ORIGIN_MATCHED, ORIGIN_PERSON, ORIGIN_SUGGESTED, ORIGIN_INFERRED ].freeze
  SWEPT_ORIGINS = [ ORIGIN_DECLARED, ORIGIN_MATCHED ].freeze
  SUGGESTION_ORIGINS = [ ORIGIN_SUGGESTED, ORIGIN_INFERRED ].freeze

  # How sure a suggestion is. Likely is two clues that agree, possible is one.
  CERTAINTY_LIKELY = "likely".freeze
  CERTAINTY_POSSIBLE = "possible".freeze
  CERTAINTIES = [ CERTAINTY_LIKELY, CERTAINTY_POSSIBLE ].freeze

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
      gone.each do |resource|
        Change.create!(workspace_id: workspace_id, resource_id: resource.id, kind: Change::KIND_REMOVED, happened_at: at)
        Chat::Memory.flag_outdated!(resource, "#{resource.name} is no longer reported by its connection")
      end
      gone.update_all(removed_at: at, updated_at: at)

      Link.where(integration_environment_id: environment_row.id, origin: SWEPT_ORIGINS).delete_all
      # A link may end at something another connection reported, such as the hostname a DNS record points at.
      elsewhere = present_ids(workspace_id, snapshot.links.flat_map { |found| [ found.from, found.to ] }.uniq - ids.keys)
      snapshot.links.each do |found|
        from, to = [ found.from, found.to ].map { |key| ids[key] || elsewhere[key] }
        next unless from && to

        Link.create!(workspace_id: workspace_id, from_resource_id: from, to_resource_id: to, relation: found.relation,
                     origin: ORIGIN_DECLARED, integration_environment: environment_row, last_seen_at: at)
      end
      environment_row.update!(map_swept_at: at, map_error: nil, map_gaps: snapshot.gaps)
    end
  end

  # A new commit on a service is a deploy, since a sweep only sees the commit that is running.
  DEPLOYED_COMMIT = "deployed_commit".freeze
  # A database branch that serves production, which is the one a service connects to.
  PRODUCTION = "production".freeze
  SHORT_COMMIT = 7

  # What a provider reported about a resource, named for a person, in the order a person reads it. Other details stay
  # for Halon and are not shown.
  DETAIL_LABELS = {
    "type" => "Type", "plan" => "Plan", "instances" => "Instances", "engine" => "Engine", "region" => "Region",
    "branch" => "Branch", DEPLOYED_COMMIT => "Running commit", PRODUCTION => "Production", "record" => "Record",
    "points_to" => "Points to", "proxied" => "Proxied", "origin" => "Origin", "origins" => "Origins", "ssl_mode" => "SSL mode",
    "certificates" => "Certificates", "waf_rules" => "WAF custom rules", "rate_limit_rules" => "Rate limiting rules",
    "cache_rules" => "Cache rules", "page_rules" => "Page rules", "dnssec" => "DNSSEC"
  }.freeze
  # Settings a change to is worth recording, since a rule that moved just before an incident is a lead.
  CONFIGURED_DETAILS = %w[ssl_mode certificates waf_rules rate_limit_rules cache_rules page_rules dnssec].freeze

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
    # A hostname several connections name keeps what each said, rather than whichever swept last.
    details = found.provider == DOMAINS ? resource.details.merge(found.details) : found.details
    resource.update!(integration_environment: environment_row, name: found.name, status: found.status || (resource.status if found.provider == DOMAINS),
                     url: found.url, details: details, last_seen_at: at, removed_at: nil)
    changes.each do |kind, from, to, detail|
      resource.changes_seen.create!(workspace_id: workspace_id, kind: kind, from_value: from, to_value: to, detail: detail, happened_at: at)
    end
    renamed = changes.find { |kind, _, _| kind == Change::KIND_RENAMED }
    Chat::Memory.flag_outdated!(resource, "#{renamed[1]} was renamed #{renamed[2]}") if renamed
    resource.id
  end
  private_class_method :upsert_resource

  def self.changes_of(resource, found)
    return [ [ Change::KIND_APPEARED, nil, nil ] ] if resource.removed_at

    before = resource.details[DEPLOYED_COMMIT]
    after = found.details[DEPLOYED_COMMIT]
    [
      ([ Change::KIND_RENAMED, resource.name, found.name ] if resource.name != found.name),
      ([ Change::KIND_DEPLOYED, before, after ] if after.present? && before != after),
      ([ Change::KIND_STATUS_CHANGED, resource.status, found.status ] if resource.status != found.status && found.status.present?),
      *configured(resource.details, found.details)
    ].compact
  end
  private_class_method :changes_of

  # A setting read before and read differently now. One read for the first time is not a change.
  def self.configured(before, after)
    CONFIGURED_DETAILS.filter_map do |key|
      next if before[key].nil? || after[key].nil? || before[key] == after[key]

      [ Change::KIND_CONFIGURED, before[key].to_s, after[key].to_s, DETAIL_LABELS.fetch(key) ]
    end
  end
  private_class_method :configured

  def self.present_ids(workspace_id, keys)
    return {} if keys.empty?

    found = keys.group_by { |provider, account, kind, _| [ provider, account, kind ] }.flat_map do |(provider, account, kind), grouped|
      Resource.present.where(workspace_id: workspace_id, provider: provider, account: account, kind: kind, external_id: grouped.map(&:last))
              .pluck(:provider, :account, :kind, :external_id, :id)
    end
    found.to_h { |provider, account, kind, external_id, id| [ [ provider, account, kind, external_id ], id ] }
  end
  private_class_method :present_ids
end

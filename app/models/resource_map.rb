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
  # What a cloud runs besides services: a virtual machine (an EC2 instance, a Droplet, a Compute Engine or Azure VM), a
  # function run on demand (a Lambda, a Cloud Function), a cluster its workloads are part of (GKE, AKS, ECS), and the
  # compute that serves a database branch, which starts, scales and suspends apart from the data it reads. A website a
  # host builds and serves is a site.
  KIND_VIRTUAL_MACHINE = "virtual_machine".freeze
  KIND_FUNCTION = "function".freeze
  KIND_CLUSTER = "cluster".freeze
  KIND_COMPUTE = "compute".freeze
  KINDS = [
    KIND_SERVICE, KIND_BUILD_SERVICE, KIND_JOB, KIND_DATABASE, KIND_BRANCH, KIND_REPOSITORY, KIND_DOMAIN, KIND_ZONE, KIND_WORKER,
    KIND_SITE, KIND_BUCKET, KIND_KV_NAMESPACE, KIND_QUEUE, KIND_DATABASE_PROXY, KIND_TUNNEL, KIND_LOAD_BALANCER, KIND_ORIGIN_POOL,
    KIND_ACCESS_APP, KIND_VIRTUAL_MACHINE, KIND_FUNCTION, KIND_CLUSTER, KIND_COMPUTE
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
  # Where a resource is defined as code. Ownership, not a dependency, so a repository failing stops nothing that runs.
  RELATION_MANAGED_BY = "managed_by".freeze
  RELATIONS = [
    RELATION_RUNS_BUILDS_OF, RELATION_BUILT_FROM, RELATION_SERVED_BY, RELATION_BRANCH_OF, RELATION_USES, RELATION_PART_OF,
    RELATION_PROTECTED_BY, RELATION_MANAGED_BY
  ].freeze
  # The links along which a failure travels.
  RUNTIME_RELATIONS = (RELATIONS - [ RELATION_MANAGED_BY ]).freeze
  RELATION_WORDS = {
    RELATION_RUNS_BUILDS_OF => "runs builds of", RELATION_BUILT_FROM => "is built from", RELATION_SERVED_BY => "is served by",
    RELATION_BRANCH_OF => "is a branch of", RELATION_USES => "uses", RELATION_PART_OF => "is part of",
    RELATION_PROTECTED_BY => "is protected by", RELATION_MANAGED_BY => "is managed in"
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

  # The repository at a code host's address, such as https://github.com/acme/web or a .git address of it, on the map
  # as the code host's own reader puts it, whichever provider names it. The code host is the registry entry whose site
  # has the address's host, so any host with a site works and nothing names one. nil for an address on no known host or
  # with no owner and name.
  def self.repository_of(url)
    uri = URI.parse(url.to_s.strip)
    host = uri.host&.downcase
    entry = host && IntegrationProvider.all.find { |each| each.site.present? && URI.parse(each.site).host&.downcase == host }
    path = uri.path.to_s.delete_prefix("/").delete_suffix("/").delete_suffix(".git")
    return unless entry && path.count("/") >= 1

    Found.new(provider: entry.key, account: path.split("/").first, kind: KIND_REPOSITORY, external_id: path, name: path,
              url: "#{entry.site.chomp('/')}/#{path}")
  rescue URI::InvalidURIError
    nil
  end

  # The same, by a code host's key and the repository's path, for a provider that names the host rather than an address.
  def self.repository(provider_key, path)
    site = IntegrationProvider.find(provider_key.to_s)&.site
    site && path.present? ? repository_of("#{site.chomp('/')}/#{path}") : nil
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

  # Something a sweep could not read, as the words a person reads and the kinds of resource it would have put on the map.
  # A gap always names its kinds, empty only for what holds no resource back (a setting, a file). A sweep with a gap that
  # names any kind takes nothing away, so what it could not read is never taken as gone.
  Gap = Data.define(:text, :kinds) do
    def initialize(text:, kinds:) = super(text: text, kinds: Array(kinds))
  end

  # What one sweep of one connection saw. A resource is named by its key, the same whichever connection reports it, so a
  # repository two services build from is one resource. gaps are what the sweep could not read (Gap), and the kinds
  # they name are unread. Only a complete read, one with no unread kind, takes away what it did not report.
  # code_files are the infrastructure files a code host's sweep read, for ResourceMap::CodeDefinitions, and code_read the
  # repositories it read in full, the only ones whose suggestions it may take away.
  Snapshot = Data.define(:resources, :links, :gaps, :code_files, :code_read) do
    def initialize(resources:, links: [], gaps: [], code_files: [], code_read: [])
      loose = gaps.reject { |gap| gap.is_a?(Gap) }
      raise ArgumentError, "a gap names the kinds it could not read (ResourceMap::Gap), not only words: #{loose.first.inspect}" if loose.any?

      super(resources:, links:, gaps: gaps.uniq, code_files:, code_read:)
    end

    def unread_kinds = gaps.flat_map(&:kinds).uniq

    def complete? = unread_kinds.empty?

    def gap_texts = gaps.map(&:text).uniq
  end

  Found = Data.define(:provider, :account, :kind, :external_id, :name, :status, :url, :details) do
    def initialize(status: nil, url: nil, details: {}, **) = super

    def key = [ provider, account, kind, external_id ]
  end

  FoundLink = Data.define(:from, :to, :relation)

  # Writes a sweep. Everything the connection reported is upserted and seen now. After a complete read, what it reported
  # before and no longer does is marked removed and its declared and matched links are replaced. A read with a gap that
  # held back any kind removes nothing, since a list it missed may hold what it no longer sees. A person's links and
  # Halon's suggestions stay.
  def self.record!(environment_row, snapshot, at: Time.current)
    workspace_id = environment_row.integration.workspace_id

    ActiveRecord::Base.transaction do
      # One sweep of a connection at a time, so the hourly run and a Sync now cannot interleave their writes.
      environment_row.lock!
      ids = snapshot.resources.uniq(&:key).to_h { |found| [ found.key, upsert_resource(workspace_id, environment_row, found, at) ] }
      if snapshot.complete?
        forget(workspace_id, environment_row, ids.values, at)
        Link.where(integration_environment_id: environment_row.id, origin: SWEPT_ORIGINS).delete_all
      end
      # A link may end at something another connection reported, such as the hostname a DNS record points at.
      elsewhere = present_ids(workspace_id, snapshot.links.flat_map { |found| [ found.from, found.to ] }.uniq - ids.keys)
      snapshot.links.each do |found|
        from, to = [ found.from, found.to ].map { |key| ids[key] || elsewhere[key] }
        next unless from && to

        Link.find_or_initialize_by(workspace_id: workspace_id, from_resource_id: from, to_resource_id: to, relation: found.relation,
                                   origin: ORIGIN_DECLARED, integration_environment: environment_row).update!(last_seen_at: at)
      end
      environment_row.update!(map_swept_at: at, map_error: nil, map_gaps: snapshot.gap_texts)
    end
  end

  # A new commit on a service is a deploy, since a sweep only sees the commit that is running.
  DEPLOYED_COMMIT = "deployed_commit".freeze
  # The provider's own tags or labels on a resource, a hash of key to value. Never shown under DETAIL_LABELS, since
  # they are the provider's words rather than facts a person reads at a glance, and kept for finding resources by.
  TAGS = "tags".freeze
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
    # A resource several connections report, such as a hostname, keeps what each said rather than whichever swept last.
    sightings = resource.sightings.merge(environment_row.id.to_s => found.details)
    reported = found.with(details: sightings.values.reduce({}, :merge))
    changes = resource.previously_new_record? ? [ [ Change::KIND_APPEARED, nil, nil ] ] : changes_of(resource, reported)
    resource.update!(integration_environment: environment_row, name: found.name, status: found.status, url: found.url,
                     details: reported.details, sightings: sightings, last_seen_at: at, removed_at: nil)
    changes.each do |kind, from, to, detail|
      resource.changes_seen.create!(workspace_id: workspace_id, kind: kind, from_value: from, to_value: to, detail: detail, happened_at: at)
    end
    renamed = changes.find { |kind, _, _| kind == Change::KIND_RENAMED }
    Chat::Memory.flag_outdated!(resource, "#{renamed[1]} was renamed #{renamed[2]}") if renamed
    resource.id
  end
  private_class_method :upsert_resource

  # What this connection used to report and no longer does. A resource another connection still reports stays, with
  # what that connection said, and one nobody reports any more is marked removed.
  def self.forget(workspace_id, environment_row, seen_ids, at)
    row = environment_row.id.to_s
    unseen = Resource.present.where(workspace_id: workspace_id).where.not(id: seen_ids)
                     .where("resource_map_resources.integration_environment_id = :id OR resource_map_resources.sightings ? :key", id: environment_row.id, key: row)
    unseen.each do |resource|
      others = resource.sightings.except(row)
      if others.any?
        resource.update!(sightings: others, details: others.values.reduce({}, :merge), integration_environment_id: others.keys.first)
      else
        resource.changes_seen.create!(workspace_id: workspace_id, kind: Change::KIND_REMOVED, happened_at: at)
        Chat::Memory.flag_outdated!(resource, "#{resource.name} is no longer reported by its connection")
        resource.update!(sightings: {}, removed_at: at)
      end
    end
  end
  private_class_method :forget

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

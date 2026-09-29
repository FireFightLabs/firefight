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

  # Read as "from runs builds of to", "from is built from to", and so on.
  RELATION_RUNS_BUILDS_OF = "runs_builds_of".freeze
  RELATION_BUILT_FROM = "built_from".freeze
  RELATION_SERVES = "serves".freeze
  RELATION_BRANCH_OF = "branch_of".freeze
  RELATION_USES = "uses".freeze
  RELATIONS = [ RELATION_RUNS_BUILDS_OF, RELATION_BUILT_FROM, RELATION_SERVES, RELATION_BRANCH_OF, RELATION_USES ].freeze

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
      ids = snapshot.resources.uniq(&:key).to_h { |found| [ found.key, upsert_resource(workspace_id, environment_row, found, at) ] }
      Resource.where(integration_environment_id: environment_row.id, removed_at: nil).where.not(id: ids.values).update_all(removed_at: at, updated_at: at)

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

  def self.upsert_resource(workspace_id, environment_row, found, at)
    resource = Resource.find_or_initialize_by(workspace_id: workspace_id, provider: found.provider, account: found.account,
                                              kind: found.kind, external_id: found.external_id)
    resource.first_seen_at ||= at
    resource.update!(integration_environment: environment_row, name: found.name, status: found.status, url: found.url,
                     details: found.details, last_seen_at: at, removed_at: nil)
    resource.id
  end
  private_class_method :upsert_resource
end

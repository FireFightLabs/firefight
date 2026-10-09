# Suggests which services use which databases from clues every sweep can check. A setting that names a store's exact
# address is a fact, which ResourceMap::HostMatcher links first. What is left is suggested, from a service and a database
# named for the same project, a setting whose name points at a store's provider (ACME_DATABASE_URL) or engine (REDIS_URL),
# and what HostMatcher could only narrow down. Two clues that agree make a likely suggestion, one a possible one.
# Nothing suggested is a fact until a person confirms it.
class ResourceMap::Matcher
  USERS = [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_JOB ].freeze
  STORES = [ ResourceMap::KIND_DATABASE, ResourceMap::KIND_BRANCH ].freeze

  ENVIRONMENTS = {
    "production" => %w[prod production prd live],
    "staging" => %w[staging stage stg],
    "development" => %w[dev development develop],
    "test" => %w[test testing qa],
    "preview" => %w[preview]
  }.flat_map { |environment, words| words.map { |word| [ word, environment ] } }.to_h.freeze
  DEFAULT_ENVIRONMENT = "production".freeze

  # Words that say what a thing is rather than whose it is, so two resources sharing one are not named for the same project.
  GENERIC = %w[main master db database app web api service server worker job jobs primary replica postgres postgresql
               pg mysql redis cache queue the].freeze
  # Words in a setting's name that say which engine it reaches, matched against what a store reports as its engine.
  ENGINE_WORDS = %w[REDIS VALKEY MONGO MONGODB MYSQL CLICKHOUSE].freeze
  CERTAINTY_ORDER = [ ResourceMap::CERTAINTY_LIKELY, ResourceMap::CERTAINTY_POSSIBLE ].freeze

  Candidate = Data.define(:user, :store, :certainty, :clues, :variables) do
    def initialize(variables: [], **) = super
  end

  def initialize(workspace)
    @workspace = workspace
  end

  # Links what settings name exactly, then brings the open suggestions in line with what the map supports now. One
  # that still holds keeps its id, so a person can confirm it from a page loaded before the sweep. A suggestion someone
  # confirmed or dismissed stays as they left it, and a pair already linked any other way is not suggested again. Every
  # connection's sweep runs this for the whole workspace, so a lock keeps two from writing the same pair at once.
  def run!
    ResourceMap::Link.transaction do
      self.class.lock!(@workspace)
      hosts = ResourceMap::HostMatcher.new(@workspace)
      hosts.run!
      found = candidates(hosts.suggestions)
      open = ResourceMap::Link.where(workspace: @workspace, origin: ResourceMap::ORIGIN_INFERRED, relation: ResourceMap::RELATION_USES,
                                     confirmed_at: nil, dismissed_at: nil)
                              .index_by { |link| [ link.from_resource_id, link.to_resource_id ] }
      taken = ResourceMap::Link.where(workspace: @workspace, relation: ResourceMap::RELATION_USES).where.not(id: open.values.map(&:id))
                               .pluck(:from_resource_id, :to_resource_id).to_set
      wanted = found.reject { |candidate| taken.include?([ candidate.user.id, candidate.store.id ]) }
      ResourceMap::Link.write_all(wanted.map { |candidate| row(candidate) })
      stale = open.keys - wanted.map { |candidate| [ candidate.user.id, candidate.store.id ] }
      ResourceMap::Link.where(id: stale.map { |pair| open[pair].id }).delete_all
      found
    end
  end

  # One per workspace, held by everything that writes Firefight's own uses links, until the transaction ends.
  def self.lock!(workspace)
    key = Zlib.crc32("resource_map_matcher:#{workspace.id}")
    ResourceMap::Link.connection.select_value(ResourceMap::Link.sanitize_sql_array([ "SELECT pg_advisory_xact_lock(?)::text", key ]))
  end

  # Every suggestion the map supports, one per pair, its clues gathered. host_suggestions are HostMatcher's.
  def candidates(host_suggestions = [])
    by_pair = (named_for_project + named_in_settings + host_suggestions.map { |match| Candidate.new(**match.to_h) })
              .group_by { |candidate| [ candidate.user.id, candidate.store.id ] }
    by_pair.map { |_, found| combined(found) }
  end

  private

  def row(candidate)
    { workspace_id: @workspace.id, from_resource_id: candidate.user.id, to_resource_id: candidate.store.id, relation: ResourceMap::RELATION_USES,
      origin: ResourceMap::ORIGIN_INFERRED, certainty: candidate.certainty, clues: candidate.clues, variables: candidate.variables,
      last_seen_at: Time.current }
  end

  # Clues about one pair from several places agree, so the pair is likely. Its words are the project match's first.
  def combined(found)
    return found.first if found.one?

    found.first.with(certainty: ResourceMap::CERTAINTY_LIKELY, clues: found.flat_map(&:clues).uniq, variables: found.flat_map(&:variables).uniq.sort)
  end

  # A service and a database that share a project word, found in SQL so a large map is never read whole. Only the pairs
  # sharing a word come back, and each is judged here as before.
  def named_for_project = @named_for_project ||= project_candidates

  def project_candidates
    skipped = GENERIC + ENVIRONMENTS.keys
    pairs = ResourceMap::Resource.connection.select_rows(ResourceMap::Resource.sanitize_sql_array([ <<~SQL.squish, {
      WITH user_words AS (
        SELECT DISTINCT resources.id, word FROM resource_map_resources resources,
          regexp_split_to_table(lower(resources.name) || ' ' || lower(regexp_replace(resources.account, '^.*/', '')), '[^a-z0-9]+') AS word
        WHERE resources.workspace_id = :workspace AND resources.removed_at IS NULL AND resources.kind IN (:users)
      ), store_words AS (
        SELECT DISTINCT resources.id, word FROM resource_map_resources resources, regexp_split_to_table(lower(resources.name), '[^a-z0-9]+') AS word
        WHERE resources.workspace_id = :workspace AND resources.removed_at IS NULL AND resources.kind = :database
      )
      SELECT DISTINCT user_words.id, store_words.id FROM user_words JOIN store_words ON store_words.word = user_words.word
      WHERE user_words.word <> '' AND user_words.word NOT IN (:skipped)
    SQL
      workspace: @workspace.id, users: USERS, database: ResourceMap::KIND_DATABASE, skipped: skipped
    } ]))
    return [] if pairs.empty?

    users = ResourceMap::Resource.where(id: pairs.map(&:first).uniq).includes(integration_environment: :environment).index_by(&:id)
    databases = ResourceMap::Resource.where(id: pairs.map(&:last).uniq).index_by(&:id)
    production = production_branches(databases.keys)
    pairs.filter_map do |user_id, database_id|
      database = databases[database_id]
      candidate(users[user_id], production[database_id] || database, database)
    end
  end

  # A database is matched by its own name, and linked through its production branch when the map has one, since that
  # is what a service connects to.
  def production_branches(database_ids)
    branch_of = ResourceMap::Link.standing.where(workspace: @workspace, relation: ResourceMap::RELATION_BRANCH_OF, to_resource_id: database_ids)
                                 .joins(:from_resource).merge(ResourceMap::Resource.present.where(kind: ResourceMap::KIND_BRANCH))
                                 .where("COALESCE(resource_map_resources.details ->> ?, 'false') <> 'false'", ResourceMap::PRODUCTION)
                                 .pluck(:to_resource_id, :from_resource_id).to_h
    branches = ResourceMap::Resource.where(id: branch_of.values).index_by(&:id)
    branch_of.transform_values { |id| branches[id] }
  end

  def candidate(user, store, database)
    shared = (project_words(user) & words(database.name)) - GENERIC - ENVIRONMENTS.keys
    return if shared.empty?

    user_environment, assumed = environment_of(user)
    store_environment = environment_in(words(database.name))
    return if store_environment && user_environment != store_environment

    clues = [ "Both are named for #{shared.first}" ]
    if store_environment
      clues << (assumed ? "#{user.name} names no environment, so Firefight assumes #{user_environment}, like #{database.name}" : "Both are #{user_environment}")
    end
    certainty = store_environment ? ResourceMap::CERTAINTY_LIKELY : ResourceMap::CERTAINTY_POSSIBLE
    Candidate.new(user: user, store: store, certainty: certainty, clues: clues)
  end

  # A setting whose name points at a store's provider or engine and whose value Firefight could not match to an address,
  # either because the provider hides it or because no store reported it. Alone it is a possible suggestion, and only
  # when one database fits. With a project word the pair also shares, combined makes that suggestion likely.
  def named_in_settings
    rows = ResourceMap::Use.joins(:resource).merge(ResourceMap::Resource.present).where(workspace: @workspace)
                           .where(<<~SQL.squish)
                             NOT EXISTS (SELECT 1 FROM resource_map_endpoints endpoints
                                         WHERE endpoints.workspace_id = resource_map_uses.workspace_id
                                           AND endpoints.fingerprint IN (resource_map_uses.fingerprint, resource_map_uses.domain_fingerprint))
                           SQL
                           .pluck(:resource_id, :variable)
    clues = rows.filter_map { |resource_id, variable| pointed_at(variable)&.then { |pointed| [ resource_id, variable, pointed ] } }
    return [] if clues.empty?

    users = ResourceMap::Resource.where(id: clues.map(&:first).uniq).includes(integration_environment: :environment).index_by(&:id)
    project = named_for_project.to_set { |candidate| [ candidate.user.id, candidate.store.id ] }
    production = production_branches(databases.map(&:id))
    clues.flat_map do |user_id, variable, (label, stores)|
      user = users[user_id]
      fitting = stores.reject { |database| store_environment_differs?(user, database) }
      fitting.filter_map do |database|
        store = production[database.id] || database
        next unless fitting.one? || project.include?([ user_id, store.id ])

        Candidate.new(user: user, store: store, certainty: ResourceMap::CERTAINTY_POSSIBLE,
                      clues: [ "#{user.name} has a setting called #{variable}, which points at #{label}" ], variables: [ variable ])
      end
    end
  end

  # What a setting's name points at, in words, with the databases it fits. nil for a name that points at nothing on the map.
  def pointed_at(variable)
    @pointed_at ||= {}
    return @pointed_at[variable] if @pointed_at.key?(variable)

    named = ResourceMap::Use.words(variable)
    providers = IntegrationProvider.all.select { |entry| entry.setting_words.intersect?(named) }
    engines = (named & ENGINE_WORDS).map(&:downcase)
    @pointed_at[variable] = if providers.any?
      [ providers.map(&:name).to_sentence, databases.select { |database| providers.map(&:key).include?(database.provider) } ]
    elsif engines.any?
      [ "a #{engines.first.capitalize} store", databases.select { |database| words(database.details["engine"]).intersect?(engines) } ]
    end
    @pointed_at[variable] = nil if @pointed_at[variable]&.last.blank?
    @pointed_at[variable]
  end

  def databases
    @databases ||= ResourceMap::Resource.present.where(workspace: @workspace, kind: ResourceMap::KIND_DATABASE).to_a
  end

  def store_environment_differs?(user, database)
    store_environment = environment_in(words(database.name))
    store_environment.present? && environment_of(user).first != store_environment
  end

  # A service is named for its project through the account it lives in, such as the platform project firefight.
  def project_words(user) = words(user.name) | words(user.account.split("/").last)

  def environment_of(user)
    found = environment_in(words(user.name)) || environment_in(words(user.integration_environment&.environment&.name))
    found ? [ found, false ] : [ DEFAULT_ENVIRONMENT, true ]
  end

  def environment_in(words) = words.filter_map { |word| ENVIRONMENTS[word] }.first

  def words(text) = text.to_s.downcase.split(/[^a-z0-9]+/).reject(&:empty?)
end

# Suggests which services use which databases from clues every sweep can check, since no provider declares it and
# the connection string that would say so is a secret Firefight does not read. Two clues that agree make a likely
# suggestion, one a possible one. Nothing here is a fact until a person confirms it.
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

  Candidate = Data.define(:user, :store, :certainty, :clues)

  def initialize(workspace)
    @workspace = workspace
  end

  # Brings the open suggestions in line with what the map supports now. One that still holds keeps its id, so a person
  # can confirm it from a page loaded before the sweep. A suggestion someone confirmed or dismissed stays as they left
  # it, and a pair already linked any other way is not suggested again. Every connection's sweep runs this for the
  # whole workspace, so a lock keeps two from writing the same pair at once.
  def run!
    candidates = self.candidates
    ResourceMap::Link.transaction do
      lock!
      open = ResourceMap::Link.where(workspace: @workspace, origin: ResourceMap::ORIGIN_INFERRED, confirmed_at: nil, dismissed_at: nil)
                              .index_by { |link| [ link.from_resource_id, link.to_resource_id ] }
      taken = ResourceMap::Link.where(workspace: @workspace, relation: ResourceMap::RELATION_USES).where.not(id: open.values.map(&:id))
                               .pluck(:from_resource_id, :to_resource_id).to_set
      wanted = candidates.reject { |candidate| taken.include?([ candidate.user.id, candidate.store.id ]) }
      wanted.each { |candidate| keep(open[[ candidate.user.id, candidate.store.id ]], candidate) }
      stale = open.keys - wanted.map { |candidate| [ candidate.user.id, candidate.store.id ] }
      ResourceMap::Link.where(id: stale.map { |pair| open[pair].id }).delete_all
    end
    candidates
  end

  def candidates
    resources = ResourceMap::Resource.present.where(workspace: @workspace).includes(integration_environment: :environment).to_a
    users = resources.select { |resource| USERS.include?(resource.kind) }
    stores = targets(resources)
    users.flat_map { |user| stores.filter_map { |store, database| candidate(user, store, database) } }
  end

  private

  def lock!
    key = Zlib.crc32("resource_map_matcher:#{@workspace.id}")
    ResourceMap::Link.connection.select_value(ResourceMap::Link.sanitize_sql_array([ "SELECT pg_advisory_xact_lock(?)::text", key ]))
  end

  def keep(link, candidate)
    columns = { certainty: candidate.certainty, clues: candidate.clues, last_seen_at: Time.current }
    return link.update!(columns) if link

    ResourceMap::Link.create!(workspace: @workspace, from_resource: candidate.user, to_resource: candidate.store,
                              relation: ResourceMap::RELATION_USES, origin: ResourceMap::ORIGIN_INFERRED, **columns)
  end

  # A database is matched by its own name, and linked through its production branch when the map has one, since that
  # is what a service connects to.
  def targets(resources)
    databases = resources.select { |resource| resource.kind == ResourceMap::KIND_DATABASE }
    production = resources.select { |resource| resource.kind == ResourceMap::KIND_BRANCH && resource.details[ResourceMap::PRODUCTION] }.index_by(&:id)
    branch_of = ResourceMap::Link.standing.where(workspace: @workspace, relation: ResourceMap::RELATION_BRANCH_OF, from_resource_id: production.keys)
                                 .pluck(:to_resource_id, :from_resource_id).to_h
    databases.map { |database| [ production[branch_of[database.id]] || database, database ] }
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

  # A service is named for its project through the account it lives in, such as the Northflank project firefight.
  def project_words(user) = words(user.name) | words(user.account.split("/").last)

  def environment_of(user)
    found = environment_in(words(user.name)) || environment_in(words(user.integration_environment&.environment&.name))
    found ? [ found, false ] : [ DEFAULT_ENVIRONMENT, true ]
  end

  def environment_in(words) = words.filter_map { |word| ENVIRONMENTS[word] }.first

  def words(text) = text.to_s.downcase.split(/[^a-z0-9]+/).reject(&:empty?)
end

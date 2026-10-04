# One thing a connection reaches: a service, a database, a repository. Removed ones are kept, so a resource that comes
# back keeps its links and when it was first seen.
class ResourceMap::Resource < ApplicationRecord
  self.table_name = "resource_map_resources"

  belongs_to :workspace
  belongs_to :integration_environment, optional: true
  has_many :links_out, class_name: "ResourceMap::Link", foreign_key: :from_resource_id, inverse_of: :from_resource, dependent: :delete_all
  has_many :links_in, class_name: "ResourceMap::Link", foreign_key: :to_resource_id, inverse_of: :to_resource, dependent: :delete_all
  has_many :changes_seen, class_name: "ResourceMap::Change", foreign_key: :resource_id, inverse_of: :resource, dependent: :delete_all
  has_many :entry_links, class_name: "ResourceMap::EntryLink", foreign_key: :resource_id, inverse_of: :resource, dependent: :delete_all
  has_many :catalog_entries, through: :entry_links
  has_many :baselines, class_name: "ResourceMap::Baseline", foreign_key: :resource_id, inverse_of: :resource, dependent: :delete_all

  validates :provider, :account, :external_id, :name, presence: true
  validates :kind, inclusion: { in: ResourceMap::KINDS }

  scope :present, -> { where(removed_at: nil) }

  # The same identity a sweep's ResourceMap::Found carries.
  def key = [ provider, account, kind, external_id ]

  # Every enabled connection row that reports this resource, the one that reported it last first. A row of a connection
  # that is switched off or removed, or wired to an environment that was deleted, reaches nothing.
  def holders
    ids = [ integration_environment_id, *sightings.to_h.keys ].compact.map(&:to_s).uniq
    rows = IntegrationEnvironment.reachable.includes(:integration, :environment)
                                 .where(id: ids, integrations: { workspace_id: workspace_id }).index_by { |row| row.id.to_s }
    rows.values_at(*ids).compact
  end

  # The provider's own page for the first of places, each a kind and an id, that is on the map with one. nil when none is.
  def self.page_of(workspace, provider:, account:, places:)
    found = present.where(workspace: workspace, provider: provider, account: account)
                   .where(places.map { |kind, id| sanitize_sql_array([ "(kind = ? AND external_id = ?)", kind, id ]) }.join(" OR "))
                   .where.not(url: [ nil, "" ]).pluck(:kind, :external_id, :url)
    places.lazy.filter_map { |kind, id| found.find { |each| each[0] == kind && each[1] == id }&.last }.first
  end

  # How a provider's own status word reads at a glance. Providers name their states differently, so the words each one
  # uses are gathered here and anything else is unknown rather than guessed. Among them are AWS's RDS and EC2 states,
  # written as AWS writes them, and Neon's and Supabase's project and compute states.
  HEALTH_OK = "ok".freeze
  HEALTH_BUSY = "busy".freeze
  HEALTH_FAILING = "failing".freeze
  HEALTH_UNKNOWN = "unknown".freeze
  HEALTHS = [ HEALTH_OK, HEALTH_BUSY, HEALTH_FAILING, HEALTH_UNKNOWN ].freeze
  STATUS_HEALTH = {
    HEALTH_OK => %w[
      completed ready success running healthy active deployed sleeping available idle active_healthy migrations_passed
      functions_deployed
    ],
    HEALTH_BUSY => %w[
      in_progress pending deploying building starting staging queued resizing paused backing-up creating maintenance modifying
      rebooting renaming storage-optimization upgrading stopping shutting-down init coming_up going_down restoring pausing
      restarting creating_project running_migrations
    ],
    HEALTH_FAILING => %w[
      failed failure error errored crashed unhealthy down degraded storage-full restore-error inaccessible-encryption-credentials
      incompatible-network incompatible-option-group incompatible-parameters incompatible-restore active_unhealthy init_failed
      restore_failed pause_failed migrations_failed functions_failed
    ]
  }.flat_map { |health, words| words.map { |word| [ word, health ] } }.to_h.freeze

  def health = STATUS_HEALTH.fetch(status.to_s.downcase, HEALTH_UNKNOWN)

  def status_label = status&.tr("_", " ")&.capitalize

  NEIGHBORHOOD_DEPTH = 2
  NEIGHBORHOOD_LIMIT = 100

  # A resource named the way a person or Halon would, by its name or its provider's id, still present ones first.
  def self.named(workspace, reference)
    wanted = reference.to_s.strip.downcase
    return none if wanted.empty?

    where(workspace: workspace).where("lower(name) = :wanted OR lower(external_id) = :wanted", wanted: wanted)
      .order(Arel.sql("removed_at IS NOT NULL"), :provider, :account, :kind)
  end

  # Every link within depth hops of this resource, in either direction, each with the hop it was found at. A repository
  # a resource is managed in ends the walk there, or one service would pull in everything else defined beside it.
  def neighborhood(depth: NEIGHBORHOOD_DEPTH)
    hops = { id => 0 }
    frontier = [ id ]
    found = {}
    depth.times do |hop|
      links = ResourceMap::Link.standing.where(from_resource_id: frontier).or(ResourceMap::Link.standing.where(to_resource_id: frontier))
                               .includes(:from_resource, :to_resource, integration_environment: :integration).limit(NEIGHBORHOOD_LIMIT)
      frontier = links.flat_map do |link|
        found[link.id] ||= [ link, hop + 1 ]
        next [] if link.relation == ResourceMap::RELATION_MANAGED_BY

        [ link.from_resource_id, link.to_resource_id ].reject { |each| hops.key?(each) }.each { |each| hops[each] = hop + 1 }
      end.uniq
      break if frontier.empty? || found.size >= NEIGHBORHOOD_LIMIT
    end
    found.values.first(NEIGHBORHOOD_LIMIT)
  end
end

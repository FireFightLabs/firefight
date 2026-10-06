# One thing a connection reaches: a service, a database, a repository. Removed ones are kept, so a resource that comes
# back keeps its links and when it was first seen.
class ResourceMap::Resource < ApplicationRecord
  include ResourceMap::Resource::Searchable

  self.table_name = "resource_map_resources"

  belongs_to :workspace
  belongs_to :integration_environment, optional: true
  has_many :links_out, class_name: "ResourceMap::Link", foreign_key: :from_resource_id, inverse_of: :from_resource, dependent: :delete_all
  has_many :links_in, class_name: "ResourceMap::Link", foreign_key: :to_resource_id, inverse_of: :to_resource, dependent: :delete_all
  has_many :changes_seen, class_name: "ResourceMap::Change", foreign_key: :resource_id, inverse_of: :resource, dependent: :delete_all
  has_many :entry_links, class_name: "ResourceMap::EntryLink", foreign_key: :resource_id, inverse_of: :resource, dependent: :delete_all
  has_many :catalog_entries, through: :entry_links
  has_many :baselines, class_name: "ResourceMap::Baseline", foreign_key: :resource_id, inverse_of: :resource, dependent: :delete_all
  has_many :uses, class_name: "ResourceMap::Use", foreign_key: :resource_id, inverse_of: :resource, dependent: :delete_all
  has_many :endpoints, class_name: "ResourceMap::Endpoint", foreign_key: :resource_id, inverse_of: :resource, dependent: :delete_all

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

  # Firefight's own words for how a resource stands, and how each reads at a glance. A provider maps its own status
  # words onto these in its definition (Integrations::Provider, status_words), so the map's words stay this small set
  # whatever the provider, and a word that is in no list reads unknown rather than guessed. A resource switched off on
  # purpose is stopped, which is busy, as paused is.
  HEALTH_OK = "ok".freeze
  HEALTH_BUSY = "busy".freeze
  HEALTH_FAILING = "failing".freeze
  HEALTH_UNKNOWN = "unknown".freeze
  HEALTHS = [ HEALTH_OK, HEALTH_BUSY, HEALTH_FAILING, HEALTH_UNKNOWN ].freeze
  STATUS_HEALTH = {
    HEALTH_OK => %w[completed ready success running healthy active deployed sleeping],
    HEALTH_BUSY => %w[in_progress pending deploying building starting staging queued resizing paused stopped],
    HEALTH_FAILING => %w[failed failure error errored crashed unhealthy down degraded unavailable]
  }.flat_map { |health, words| words.map { |word| [ word, health ] } }.to_h.freeze

  def health = STATUS_HEALTH.fetch(status.to_s.downcase, HEALTH_UNKNOWN)

  def status_label = status&.tr("_", " ")&.capitalize

  # The hostnames it answers on. A hostname answers on its own name, anything else on every present hostname a link
  # that is a fact says it serves.
  def served_hostnames
    return [ name.downcase ] if kind == ResourceMap::KIND_DOMAIN

    ResourceMap::Link.facts.where(to_resource: self, relation: ResourceMap::RELATION_SERVED_BY).includes(:from_resource).map(&:from_resource)
                     .select { |from| from.kind == ResourceMap::KIND_DOMAIN && from.removed_at.nil? }.map { |from| from.name.downcase }.uniq
  end

  NEIGHBORHOOD_DEPTH = 2
  NEIGHBORHOOD_LIMIT = 100

  # A resource named the way a person or Halon would, by its name or its provider's id, still present ones first.
  def self.named(workspace, reference)
    wanted = reference.to_s.strip.downcase
    return none if wanted.empty?

    where(workspace: workspace).where("lower(name) = :wanted OR lower(external_id) = :wanted", wanted: wanted)
      .order(Arel.sql("removed_at IS NOT NULL"), :provider, :account, :kind)
  end

  # A resource by its name, its provider's id or Firefight's own id. A provider's id can look like Firefight's, so both are tried.
  def self.referenced(workspace, reference)
    wanted = reference.to_s.strip.downcase
    return none if wanted.empty?

    by_id = " OR resource_map_resources.id = CAST(:wanted AS uuid)" if wanted.match?(CatalogEntry::ReferenceManagement::UUID_FORMAT)
    where(workspace: workspace).where("lower(resource_map_resources.name) = :wanted OR lower(resource_map_resources.external_id) = :wanted#{by_id}", wanted: wanted)
      .order(Arel.sql("resource_map_resources.removed_at IS NOT NULL"), :provider, :account, :kind)
  end

  # The one present resource principal may read by that reference, or a sentence saying nothing is called that or which
  # ones share the name, so a tool that acts on one resource refuses in the same words on every surface.
  def self.locate(workspace, principal, reference)
    found = visible_to(principal, workspace).referenced(workspace, reference.to_s).present.to_a
    return "Nothing on the resource map is called #{reference}. find_resources searches it." if found.empty?
    return found.first if found.one?

    "More than one resource is called #{reference}: #{found.map { |each| "#{each.kind} #{each.name} (map id #{each.id})" }.to_sentence}. Name it by its map id."
  end

  # One line saying what it is and where it runs, for a reader that has no room for a fact sheet.
  def line
    environment = integration_environment&.environment&.name
    place = [ ResourceMap.provider_name(provider), account ].join(" ")
    [ "#{kind.humanize(capitalize: false)} #{name} on #{place}", ("in #{environment}" if environment), (status_label&.downcase || "status unknown"),
      ("gone since #{removed_at.to_date.iso8601}" if removed_at) ].compact.join(", ")
  end

  # The resources principal may read on workspace's map. A resource is in the environments of the connection rows that
  # report it, so one that only a connection wired to no environment reports needs every environment.
  def self.visible_to(principal, workspace)
    environments = environments_visible_to(principal, workspace)
    in_workspace = where(workspace: workspace)
    return in_workspace if environments.nil?
    return none if environments.empty?

    in_workspace.where(<<~SQL.squish, environments: environments)
      EXISTS (SELECT 1 FROM integration_environments reporting WHERE reporting.catalog_entry_id IN (:environments)
              AND (reporting.id = resource_map_resources.integration_environment_id
                   OR resource_map_resources.sightings ? CAST(reporting.id AS text)))
    SQL
  end

  # The environments principal reads the map in, as catalog entry ids: nil for every one, empty for none.
  def self.environments_visible_to(principal, workspace)
    reach = AbilityGateway.reach(principal: principal, action_key: Ability::Action::MAP_READ, workspace: workspace)
    return [] if reach.nil?

    reach[Ability::Scope::DIMENSION_ENVIRONMENT]
  end

  # Every link within depth hops of this resource, in either direction, each with the hop it was found at. A repository
  # a resource is managed in ends the walk there, or one service would pull in everything else defined beside it. With
  # within, only links between two resources inside it are walked.
  def neighborhood(depth: NEIGHBORHOOD_DEPTH, within: nil) = walk(depth, within).first

  # How many links the same walk left out because their other end is outside within, so a fact sheet can say the map
  # goes on without saying where.
  def links_out_of_reach(within, depth: NEIGHBORHOOD_DEPTH) = walk(depth, within).last

  private

  def walk(depth, within)
    @walks ||= {}
    @walks[[ depth, within&.to_sql ]] ||= begin
      hops = { id => 0 }
      frontier = [ id ]
      found = {}
      hidden = Set.new
      depth.times do |hop|
        links = ResourceMap::Link.standing.where(from_resource_id: frontier).or(ResourceMap::Link.standing.where(to_resource_id: frontier))
                                 .includes(:from_resource, :to_resource, integration_environment: :integration).limit(NEIGHBORHOOD_LIMIT).to_a
        if within
          ends = links.flat_map { |link| [ link.from_resource_id, link.to_resource_id ] }.uniq
          seen = within.where(id: ends).pluck(:id).to_set
          hidden.merge(links.reject { |link| seen.include?(link.from_resource_id) && seen.include?(link.to_resource_id) }.map(&:id))
          links = links.select { |link| seen.include?(link.from_resource_id) && seen.include?(link.to_resource_id) }
        end
        frontier = links.flat_map do |link|
          found[link.id] ||= [ link, hop + 1 ]
          next [] if link.relation == ResourceMap::RELATION_MANAGED_BY

          [ link.from_resource_id, link.to_resource_id ].reject { |each| hops.key?(each) }.each { |each| hops[each] = hop + 1 }
        end.uniq
        break if frontier.empty? || found.size >= NEIGHBORHOOD_LIMIT
      end
      [ found.values.first(NEIGHBORHOOD_LIMIT), hidden.size ]
    end
  end
end

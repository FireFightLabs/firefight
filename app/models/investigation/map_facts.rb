# The resources on the map an incident touches, so a run starts from where its services run rather than looking them
# up. Those its catalog services run on come first, then those the clues name, all within what the investigator may
# read. Each says what it is, what fails with it and what changed on it in the day before the incident started. Reads
# Firefight's own tables only, so the same run always gets the same facts.
class Investigation::MapFacts
  LIMIT = 10
  CHANGE_WINDOW = 24.hours
  CHANGES_SHOWN = 10
  # The clues that can name a resource, by the name it has on the map.
  NAMING_CLUES = %w[names repositories].freeze

  def initialize(investigation, incident, clues)
    @investigation = investigation
    @incident = incident
    @clues = clues
  end

  def resources = found.first(LIMIT).map { |resource, why| facts(resource, why) }

  def held_back = [ found.size - LIMIT, 0 ].max

  private

  def visible = @visible ||= ResourceMap::Resource.visible_to(@investigation.acting_principal, @investigation.workspace)

  def started = @started ||= Time.iso8601(@clues.dig("started", "at"))

  # Each resource once, with why it is here, in an order that does not change between reads.
  def found
    @found ||= begin
      chosen = {}
      services.each { |resource, entries| chosen[resource] ||= "runs #{entries.map(&:name).sort.to_sentence}" }
      named.each { |resource, source| chosen[resource] ||= "named in #{source}" }
      chosen.to_a
    end
  end

  def services
    entries = @incident.catalog_services.index_by(&:id)
    return [] if entries.empty?

    links = ResourceMap::EntryLink.where(catalog_entry_id: entries.keys, resource_id: visible.present.select(:id))
                                  .includes(resource: { integration_environment: :environment }).to_a
    links.group_by(&:resource).map { |resource, linked| [ resource, linked.map { |link| entries.fetch(link.catalog_entry_id) } ] }
         .sort_by { |resource, _| [ resource.name.downcase, resource.id ] }
  end

  def named
    NAMING_CLUES.flat_map { |key| Array(@clues[key]) }.flat_map do |clue|
      visible.present.named(@investigation.workspace, clue["value"]).includes(integration_environment: :environment)
             .sort_by(&:id).map { |resource| [ resource, clue["source"] ] }
    end
  end

  def facts(resource, why)
    radius = ResourceMap::BlastRadius.new(resource, within: visible)
    {
      "id" => resource.id, "name" => resource.name, "line" => resource.line, "why" => why,
      "dependents" => radius.total, "dependents_by_kind" => radius.by_kind.presence,
      "changes_before_start" => changes(resource).presence
    }.compact
  end

  def changes(resource)
    found = resource.changes_seen.where(happened_at: (started - CHANGE_WINDOW)..started).includes(:resource).order(:happened_at, :id).to_a
    lines = found.last(CHANGES_SHOWN).map(&:line)
    found.size > CHANGES_SHOWN ? [ "#{found.size - CHANGES_SHOWN} earlier changes not shown", *lines ] : lines
  end
end

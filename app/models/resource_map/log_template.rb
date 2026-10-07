# One kind of line a resource usually logs, as ResourceMap::LogMiner masks and groups them, such as
# "GET /health <NUM> in <NUM> ms". A daily read samples a week of its logs, so a pattern seen here is one the resource
# prints in an ordinary week, and Halon can tell a new kind of line from one that was always there. The pattern is
# encrypted, since masking can miss a value, and found again by a keyed digest.
class ResourceMap::LogTemplate < ApplicationRecord
  self.table_name = "resource_map_log_templates"

  # The most patterns kept for one resource, the ones with the most lines.
  KEPT = 200
  # A pattern no read has seen for this long is no longer usual.
  WINDOW = 7.days
  SHOWN = 10
  # What the daily read covers: app kinds that run a catalog entry, anything whose services had incidents in this many
  # days, and the most depended on.
  APP_KINDS = [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_WORKER, ResourceMap::KIND_JOB, ResourceMap::KIND_FUNCTION ].freeze
  INCIDENT_DAYS = 90
  MOST_DEPENDED_ON = 50

  encrypts :template

  belongs_to :workspace
  belongs_to :resource, class_name: "ResourceMap::Resource"
  # The connection whose logs it was read from.
  belongs_to :integration_environment

  scope :this_week, -> { where(last_seen_at: WINDOW.ago..) }
  scope :most_lines_first, -> { order(lines: :desc, last_seen_at: :desc, id: :asc) }

  # Keeps what one read found for a resource: each pattern's lines in this read, how many reads have seen it, and when
  # it was first and last seen. A pattern no read has seen in a week goes, and only the keep with the most lines stay.
  def self.record!(environment_row, resource, patterns, at: Time.current, keep: KEPT)
    rows = alike_known(resource, patterns).map do |pattern|
      { workspace_id: resource.workspace_id, resource_id: resource.id, integration_environment_id: environment_row.id,
        digest: ResourceMap::Fingerprint.of_log_template(pattern.template, resource.workspace_id),
        template: pattern.template, level: pattern.level, lines: pattern.lines, samples: 1,
        first_seen_at: at, last_seen_at: at, created_at: at, updated_at: at }
    end
    transaction do
      if rows.any?
        upsert_all(rows, unique_by: %i[resource_id digest], on_duplicate: Arel.sql(
          "lines = EXCLUDED.lines, level = EXCLUDED.level, template = EXCLUDED.template, " \
          "integration_environment_id = EXCLUDED.integration_environment_id, last_seen_at = EXCLUDED.last_seen_at, " \
          "updated_at = EXCLUDED.updated_at, samples = resource_map_log_templates.samples + 1"
        ))
      end
      where(resource_id: resource.id).where(last_seen_at: ...(at - WINDOW)).delete_all
      kept = where(resource_id: resource.id).most_lines_first.limit(keep).select(:id)
      where(resource_id: resource.id).where.not(id: kept).delete_all
    end
    rows.size
  end

  # A pattern a kept one already covers is counted as that one, so "user eve logged in" read alone one day joins the
  # "user <*> logged in" read before, rather than starting a pattern of its own.
  def self.alike_known(resource, patterns)
    known = ResourceMap::LogMiner.known_by(where(resource_id: resource.id).pluck(:template))
    patterns.group_by { |pattern| known.known(pattern.template) || pattern.template }.map do |template, alike|
      ResourceMap::LogMiner::Pattern.new(template: template, lines: alike.sum(&:lines), level: alike.map(&:level).compact.min_by { |level| ResourceMap::LogMiner::LEVELS.index(level) })
    end
  end
  private_class_method :alike_known

  # How a person or Halon reads it, such as "ERROR timeout after <NUM> ms (error, 40 lines in the last read, seen in 6 reads)".
  def line
    level_words = "#{level}, " if level
    "#{template} (#{level_words}#{lines} #{'line'.pluralize(lines)} in the last read, seen in #{samples} #{'read'.pluralize(samples)})"
  end

  # The resources the daily read covers, those with incidents first, capped by the sweep per connection.
  def self.scope_of(workspace)
    present = ResourceMap::Resource.present.where(workspace: workspace)
    linked = ResourceMap::EntryLink.joins(:catalog_entry).where(workspace: workspace, catalog_entries: { deleted_at: nil })
    struck = IncidentFieldValue.joins(:incident).where(incidents: { workspace_id: workspace.id, created_at: INCIDENT_DAYS.days.ago.. })
                               .where.not(catalog_entry_id: nil).select(:catalog_entry_id)
    with_incidents = present.where(id: linked.where(catalog_entry_id: struck).select(:resource_id)).order(:name).to_a
    running = present.where(kind: APP_KINDS, id: linked.select(:resource_id)).order(:name).to_a
    (with_incidents + running + depended_on(workspace)).uniq(&:id)
  end

  # The most depended on, among those anything depends on at all.
  def self.depended_on(workspace)
    top = ResourceMap::Query.new(workspace, sort: ResourceMap::Query::SORT_DEPENDENTS).page(limit: MOST_DEPENDED_ON).resources
    counts = ResourceMap::Resource.where(id: top.map(&:id)).pluck(:id, Arel.sql(ResourceMap::Query.dependents_sql("resource_map_resources.id"))).to_h
    top.select { |resource| counts[resource.id].to_i.positive? }
  end

  # What a reading of recent logs found against the resource's usual patterns: the patterns not seen this week, and the
  # error patterns that are usual, which alone explain nothing.
  Comparison = Data.define(:lines_read, :usual, :new_patterns, :usual_errors)

  def self.compare(resource, lines)
    usual = where(resource_id: resource.id).this_week.most_lines_first.to_a
    known = ResourceMap::LogMiner.known_by(usual.map(&:template))
    by_template = usual.index_by(&:template)
    mined = ResourceMap::LogMiner.mine(lines)
    fresh, seen = mined.partition { |pattern| known.known(pattern.template).nil? }
    errors = seen.filter_map do |pattern|
      kept = by_template[known.known(pattern.template)]
      [ pattern, kept ] if pattern.level == ResourceMap::LogMiner::LEVEL_ERROR || kept&.level == ResourceMap::LogMiner::LEVEL_ERROR
    end
    Comparison.new(lines_read: lines.size, usual: usual.size, new_patterns: fresh, usual_errors: errors)
  end

  NEW_SHOWN = 25
  ERRORS_SHOWN = 10
  # The most lines new_log_patterns asks for.
  LINES = 2_000
  DESCRIPTION = "Which kinds of log line a resource printed recently that it did not print in the last week, from its recent " \
                "logs grouped into patterns with numbers, ids and quoted values masked, and which of the error patterns it " \
                "printed are usual, so a line that was always there is not taken for the cause".freeze
  SCHEMA = {
    "type" => "object",
    "properties" => {
      "resource" => { "type" => "string", "description" => "The resource, by its name, its provider's id or its id on the resource map" },
      "minutes" => { "type" => "integer", "description" => "How far back from now, in minutes (optional, #{ResourceMap::KeyQueries::DEFAULT_MINUTES})" }
    },
    "required" => %w[resource]
  }.freeze

  # What new_log_patterns answers, in words Halon and an outside agent read.
  def self.report(resource, comparison, from:, minutes:)
    head = "Read #{comparison.lines_read} log #{'line'.pluralize(comparison.lines_read)} of #{resource.name} from #{from} over the last #{minutes} minutes."
    return "#{head} None came back, so there is nothing to compare." if comparison.lines_read.zero?

    known = if comparison.usual.zero?
      "No usual log lines are known for #{resource.name} yet, so every pattern counts as new."
    else
      "#{comparison.usual} usual #{'pattern'.pluralize(comparison.usual)} were seen in the last week."
    end
    fresh = if comparison.new_patterns.empty?
      "No pattern is new this week."
    else
      shown = comparison.new_patterns.first(NEW_SHOWN).map { |pattern| "- #{"[#{pattern.level}] " if pattern.level}#{pattern.template} (#{pattern.lines} #{'line'.pluralize(pattern.lines)})" }
      more = comparison.new_patterns.size - NEW_SHOWN
      [ "Not seen in the last week, most lines first:", *shown, ("#{more} more new patterns are not listed." if more.positive?) ].compact.join("\n")
    end
    errors = comparison.usual_errors.first(ERRORS_SHOWN).map do |pattern, kept|
      "- #{pattern.template} (#{pattern.lines} #{'line'.pluralize(pattern.lines)} now#{", seen in #{kept.samples} daily #{'read'.pluralize(kept.samples)}" if kept})"
    end
    usual_errors = [ "Error patterns that are usual, seen in the last week, so not the cause by themselves:", *errors ].join("\n") if errors.any?
    [ "#{head} #{known}", fresh, usual_errors ].compact.join("\n\n")
  end

  # Why a resource has no usual log lines, worked out live: no connection reads its logs for principal, it is outside
  # what the daily read covers, or it has not been read yet. nil when it has some.
  def self.missing_reason(resource, principal)
    return if where(resource_id: resource.id).this_week.exists?

    begin
      Integrations::Capabilities.resolve(resource.workspace, Integrations::Capabilities::LOGS, { Integrations::Capabilities::RESOURCE_ARG => resource.id },
                                         principal: principal)
    rescue Integrations::Capabilities::Unroutable => error
      return "Its logs cannot be read, so its usual lines are not known. #{error.message}"
    end
    unless scope_of(resource.workspace).any? { |each| each.id == resource.id }
      return "Firefight learns the usual log lines of services, workers, jobs and functions that run a catalog entry, of " \
             "resources whose services had incidents in the last #{INCIDENT_DAYS} days, and of the #{MOST_DEPENDED_ON} most depended on. " \
             "Link it to the catalog entry it runs to have them read."
    end

    "Not read yet. They are read once a day, after what normal looks like."
  end
end

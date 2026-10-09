# Which resources on the map are defined as code, read off the infrastructure files a code host's sweep could see. A
# resource named in a Terraform file, a Helm chart or a platform's config is suggested as managed in that repository,
# so a fix changes the code rather than the resource, which the next apply would undo. A name is a clue, not proof, so
# every link is a suggestion until a person confirms it.
class ResourceMap::CodeDefinitions
  MAX_CLUES = 3
  # Shorter names match too much to mean anything, and short ones only count beside their provider.
  MIN_NAME = 3
  SHORT_NAME = 5
  # How many lines from a name its provider may be named and still be about the same resource.
  NEARBY_LINES = 10
  # Kinds that are not run from code, or are the code itself.
  SKIPPED_KINDS = [ ResourceMap::KIND_REPOSITORY, ResourceMap::KIND_BRANCH ].freeze
  # Values every config file is full of, which name nothing.
  STOP_WORDS = %w[true false null none yes no default enabled disabled latest always never auto].freeze
  TOKEN = /[a-z0-9][a-z0-9_.-]*[a-z0-9]/
  # Only values are read for names, never keys: a quoted string, or what follows a YAML key or list dash.
  VALUES = /"([^"\n]*)"|'([^'\n]*)'|^\s*(?:-\s+)?[\w.\/-]+:\s+([^\s"'{\[#|>&*!][^#\n]*)|^\s*-\s+([^\s"'{\[#:][^#:\n]*)$/
  # Words around a hostname that say it is being declared, not only called.
  DECLARES_HOST = /record|dns|route|custom_domain|domain|zone|cname|hostname|ingress|host:/

  Candidate = Data.define(:resource, :repository, :certainty, :clues)

  def initialize(workspace)
    @workspace = workspace
  end

  # Brings the suggestions in line with what the files say now. One that still holds keeps its id, a suggestion someone
  # confirmed or dismissed stays as they left it, and a pair already linked another way is not suggested again. Only a
  # repository read in full takes a suggestion away, so a partial read never loses one. A suggestion whose connection
  # was removed is taken up by the next one to read it.
  def record!(environment_row, files, read_in_full:)
    return [] if files.empty? && read_in_full.empty?

    found = candidates(files)
    ResourceMap::Link.transaction do
      lock!
      open = ResourceMap::Link.where(workspace: @workspace, origin: ResourceMap::ORIGIN_INFERRED, relation: ResourceMap::RELATION_MANAGED_BY,
                                     integration_environment: [ environment_row, nil ], confirmed_at: nil, dismissed_at: nil)
                              .includes(:to_resource).index_by { |link| [ link.from_resource_id, link.to_resource_id ] }
      taken = ResourceMap::Link.where(workspace: @workspace, relation: ResourceMap::RELATION_MANAGED_BY).where.not(id: open.values.map(&:id))
                               .pluck(:from_resource_id, :to_resource_id).to_set
      wanted = found.reject { |candidate| taken.include?(pair(candidate)) }
      wanted.each { |candidate| keep(environment_row, open[pair(candidate)], candidate) }
      stale = (open.keys - wanted.map { |candidate| pair(candidate) }).map { |key| open[key] }
      provider = environment_row.integration.provider
      gone = stale.select { |link| link.to_resource.provider == provider && read_in_full.include?(link.to_resource.external_id) }
      ResourceMap::Link.where(id: gone.map(&:id)).delete_all
    end
    found
  end

  def candidates(files)
    # By host and path, since a project mirrored on two hosts is two repositories.
    repositories = ResourceMap::Resource.present.where(workspace: @workspace, kind: ResourceMap::KIND_REPOSITORY).index_by { |resource| [ resource.provider, resource.external_id ] }
    by_name = ResourceMap::Resource.present.where(workspace: @workspace).where.not(kind: SKIPPED_KINDS).to_a
                                   .select { |resource| resource.name.length >= MIN_NAME && STOP_WORDS.exclude?(resource.name.downcase) }
                                   .group_by { |resource| resource.name.downcase }
    found = Hash.new { |hash, key| hash[key] = [] }
    files.each do |file|
      repository = repositories[[ file.provider, file.repository ]]
      next unless repository

      lines = file.content.downcase.lines
      named_on(lines).each do |name, line_numbers|
        by_name[name]&.each { |resource| found[[ resource, repository ]] << [ file, sure?(resource, lines, line_numbers) ] }
      end
    end
    found.filter_map { |(resource, repository), sightings| candidate(resource, repository, sightings) }
  end

  private

  def lock!
    key = Zlib.crc32("resource_map_code_definitions:#{@workspace.id}")
    ResourceMap::Link.connection.select_value(ResourceMap::Link.sanitize_sql_array([ "SELECT pg_advisory_xact_lock(?)::text", key ]))
  end

  # Each name a file gives as a value, with the lines it is on.
  def named_on(lines)
    lines.each_with_index.with_object(Hash.new { |hash, key| hash[key] = [] }) do |(line, number), named|
      line.scan(VALUES).flatten.compact.each { |value| value.scan(TOKEN).each { |token| named[token] << number } }
    end
  end

  # A hostname counts when the lines around it declare one. Anything else counts when its provider is named nearby,
  # which a Terraform resource type does inside a longer word, such as <provider>_service.
  def sure?(resource, lines, line_numbers)
    words = resource.kind == ResourceMap::KIND_DOMAIN ? DECLARES_HOST : resource.provider.downcase
    line_numbers.any? do |number|
      lines[[ number - NEARBY_LINES, 0 ].max..(number + NEARBY_LINES)].any? { |line| words.is_a?(Regexp) ? line.match?(words) : line.include?(words) }
    end
  end

  # A generic or short name only counts beside its provider.
  def candidate(resource, repository, sightings)
    sure = sightings.any?(&:last)
    name = resource.name.downcase
    return if !sure && (ResourceMap::Matcher::GENERIC.include?(name) || name.length < SHORT_NAME)

    clues = sightings.uniq { |file, _| file.path }.first(MAX_CLUES).map do |file, nearby|
      "Named in #{file.path} (#{file.tool})#{', beside its provider' if nearby && resource.kind != ResourceMap::KIND_DOMAIN} #{file.url}"
    end
    Candidate.new(resource: resource, repository: repository, certainty: sure ? ResourceMap::CERTAINTY_LIKELY : ResourceMap::CERTAINTY_POSSIBLE,
                  clues: clues)
  end

  def pair(candidate) = [ candidate.resource.id, candidate.repository.id ]

  def keep(environment_row, link, candidate)
    columns = { certainty: candidate.certainty, clues: candidate.clues, last_seen_at: Time.current, integration_environment: environment_row }
    return link.update!(columns) if link

    ResourceMap::Link.create!(workspace: @workspace, from_resource: candidate.resource, to_resource: candidate.repository,
                              relation: ResourceMap::RELATION_MANAGED_BY, origin: ResourceMap::ORIGIN_INFERRED, **columns)
  end
end

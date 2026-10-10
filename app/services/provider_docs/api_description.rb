module ProviderDocs
  # A provider's API description written out as the reference its general read (Integrations::ApiReads) is used with.
  # Only the reads are written, since that is all a general read sends. A description that did not change since its
  # revision is not written again.
  class ApiDescription
    Read = Data.define(:area, :call, :summary, :description, :parameters, :answers)
    Parameter = Data.define(:name, :where, :type, :required, :description)
    FORMATS = {
      "openapi" => "ProviderDocs::ApiDescription::OpenApi",
      "discovery" => "ProviderDocs::ApiDescription::Discovery",
      "botocore" => "ProviderDocs::ApiDescription::Botocore",
      "graphql" => "ProviderDocs::ApiDescription::Graphql"
    }.freeze
    # An API's whole description is far larger than a page of documentation, so it may be read up to this size.
    MAX_BYTES = 80_000_000
    DESCRIPTION_LIMIT = 600
    PARAMETER_LIMIT = 300
    ANSWER_FIELDS = 40
    INDEX = "index.md".freeze

    def initialize(definition, client:, revisions:, progress:)
      @definition = definition
      @client = client
      @revisions = revisions
      @progress = progress
    end

    # A description split over several files, as a cloud's often is, is read whole each time and written as one.
    def read
      addresses = Array(@definition.address)
      known = addresses.one? ? @revisions.values.compact.first : nil
      answers = addresses.map { |address| @client.file(address, revision: known, max_bytes: MAX_BYTES) }
      return unchanged(answers.first) if answers.one? && answers.first.body.nil? && @revisions.any?
      raise DocsClient::Error, "#{addresses.first} answered nothing" if answers.any? { |answer| answer.body.nil? }

      described = answers.map { |answer| FORMATS.fetch(@definition.fetch("format")).constantize.new(parsed(answer.body), @definition) }
      reads = described.flat_map(&:reads).select { |each| included?(each) }.uniq(&:call)
      raise DocsClient::Error, "#{addresses.first} describes no reads" if reads.empty?

      revision = answers.map(&:revision).join(" ")
      pages = pages_of(described.first, reads).map { |path, content| Fetched.new(path: path, url: addresses.first, content: content, revision: revision) }
      @progress.listed(pages.size)
      Reading.new(pages: pages, listed: pages.map(&:path), version: revision, license: @definition.fetch("license"))
    end

    private

    def unchanged(answer)
      @progress.listed(@revisions.size)
      pages = @revisions.keys.map { |path| Fetched.new(path: path, url: @definition.address, content: nil, revision: answer.revision) }
      Reading.new(pages: pages, listed: @revisions.keys, version: answer.revision, license: @definition.fetch("license"))
    end

    # YAML builds nothing beyond plain data and dates.
    def parsed(text)
      text.lstrip.start_with?("{") ? JSON.parse(text) : YAML.safe_load(text, permitted_classes: [ Date, Time ], aliases: true)
    rescue Psych::Exception => error
      raise DocsClient::Error, "#{@definition.address} could not be read: #{error.message}"
    end

    # include keeps only the reads whose path starts with one of its prefixes, and leave_out drops those whose path holds
    # one of its parts, such as the watch paths an API keeps only for old clients.
    def included?(each)
      path = each.call.split(" ", 2).last
      only = Array(@definition["include"])
      (only.empty? || only.any? { |start| path.start_with?(start) }) && Array(@definition["leave_out"]).none? { |part| path.include?(part) }
    end

    def folder = "#{@definition.prefix}#{@definition.fetch('endpoints')}"

    def pages_of(parsed, reads)
      areas = reads.group_by(&:area).sort_by { |area, _| area.downcase }
      index = [ "# #{parsed.title} reads", "", parsed.preface, "",
                *areas.flat_map { |area, each| [ "## #{area}", "", "Detail in #{folder}/#{slug(area)}.md.", "", *each.map { |one| "- #{one.call}#{": #{one.summary}" if one.summary.present?}" }, "" ] } ]
      { "#{folder}/#{INDEX}" => index.join("\n") }.merge(
        areas.to_h { |area, each| [ "#{folder}/#{slug(area)}.md", area_page(parsed, area, each) ] }
      )
    end

    def area_page(parsed, area, reads)
      lines = [ "# #{area}", "", "#{parsed.title}. #{parsed.preface}", "" ]
      reads.sort_by(&:call).each do |each|
        lines << "## #{each.call}" << ""
        lines << clean(each.summary) << "" if each.summary.present?
        lines << clean(each.description, DESCRIPTION_LIMIT) << "" if each.description.present? && clean(each.description) != clean(each.summary)
        each.parameters.group_by(&:where).each do |where, parameters|
          lines << "#{where.to_s.capitalize}:"
          parameters.each { |parameter| lines << "- #{parameter.name} (#{[ parameter.type.presence, ('required' if parameter.required) ].compact.join(', ')})#{": #{clean(parameter.description, PARAMETER_LIMIT)}" if parameter.description.present?}" }
          lines << ""
        end
        lines << "Answers: #{each.answers.first(ANSWER_FIELDS).join(', ')}#{', ...' if each.answers.size > ANSWER_FIELDS}" << "" if each.answers.any?
      end
      lines.join("\n")
    end

    def slug(area) = area.to_s.parameterize.presence || "other"

    def clean(text, limit = nil)
      words = text.to_s.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
      limit ? words.truncate(limit, separator: " ") : words
    end
  end
end

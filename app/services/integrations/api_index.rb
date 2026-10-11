module Integrations
  # A provider's key reads through its general tool (api_read, Northflank's api_request, Cloudflare's execute), at most
  # LIMIT of them, kept in config/api_indexes/<provider>.yml: what an investigation reaches for most, such as deployments,
  # builds, logs, audit logs and certificates, each with its path, a line on what it answers and the query parameters
  # that matter. Its text closes the provider's API skill, so Halon finds a path there rather than guessing one, and a
  # read that fails on a path the index does not hold answers with the nearest ones it does (hint).
  #
  # A file names the tool, the skill its text closes, and either the docs store folder its reads are checked against
  # (reference) or the address of the provider's own API reference they were taken from (source), for a provider whose
  # reference is not openly licensed. shape says how a call names a read: path (method and path), operation (an AWS
  # service's operation) or graphql (a field of the query type). Each read has its call as the reference heads it, and a
  # service where the reference files its reads by service. bin/rails provider_docs:api_indexes keeps them in step with
  # the docs store (ApiIndex::Refresh). Only reads are ever listed.
  class ApiIndex
    DIRECTORY = Rails.root.join("config/api_indexes")
    LIMIT = 40
    NEAREST = 3
    SHAPE_PATH = "path".freeze
    SHAPE_OPERATION = "operation".freeze
    SHAPE_GRAPHQL = "graphql".freeze
    SHAPES = [ SHAPE_PATH, SHAPE_OPERATION, SHAPE_GRAPHQL ].freeze
    GET = "GET".freeze
    QUERY_FIELD = "query".freeze
    # The text's first line, which the skill's own steps end before.
    HEADING = "Key reads, the ones an investigation reaches for most, with what to fill in braces and the query parameters " \
              "that matter. The API reference lists every other read.".freeze
    PLACEHOLDER = /\{[^}]+\}/
    # The request Firefight writes for a read in a guard's own shape (ReadGuards::Cloudflare), whose path is a JSON string.
    WRITTEN_PATH = /"path"\s*:\s*"([^"]+)"/
    WRITTEN_METHOD = /"method"\s*:\s*"([A-Z]+)"/
    GRAPHQL_FIELD = /\{\s*(?:\w+\s*:\s*)?(\w+)/

    Read = Data.define(:call, :service, :purpose, :query) do
      def verb = call.split(" ", 2).first

      def path = call.split(" ", 2).last

      # A query parameter written name=value takes that value, such as Azure's api-version.
      def query_names = query.map { |each| each.split("=", 2).first }
    end

    class << self
      # The provider's index, or nil when it keeps none.
      def for(provider_key)
        key = provider_key.to_s
        return nil unless key.match?(Provider::KEY_FORMAT)

        indexes.fetch(key) { indexes[key] = load(key) }
      end

      def all = Dir[DIRECTORY.join("*.yml")].map { |path| self.for(File.basename(path, ".yml")) }.compact.sort_by(&:provider)

      # Words to add to a failed call through the provider's general tool, naming the nearest key reads, or nil when the
      # call is one the index holds, so a failure on a listed read is never sent looking elsewhere.
      def hint(provider_key, tool_name, arguments) = self.for(provider_key)&.hint(tool_name, arguments)

      # The hint for a call that failed. A refusal by Firefight's own rule, a rate limit or a slow provider says nothing
      # about the path, so those are left as they are.
      def hint_after(error, provider_key, tool_name, arguments)
        return nil if [ PolicyRefusal, RateLimited, TimedOut, Unavailable ].any? { |kind| error.is_a?(kind) }

        hint(provider_key, tool_name, arguments)
      end

      # A remote server's answer with the hint after it, when the server said the call failed.
      def hinted(result, provider_key, tool_name, arguments, failed:)
        hint = failed ? hint(provider_key, tool_name, arguments) : nil
        hint ? result.merge("content" => [ *result["content"], { "type" => "text", "text" => hint } ]) : result
      end

      def load(key)
        file = DIRECTORY.join("#{key}.yml")
        return nil unless file.exist?

        new(key, YAML.safe_load_file(file))
      end

      private

      def indexes = @indexes ||= {}
    end

    attr_reader :provider, :tool, :skill, :shape, :reference, :source, :reads

    def initialize(provider, data)
      @provider = provider
      @tool = data.fetch("tool")
      @skill = data.fetch("skill")
      @shape = data.fetch("shape", SHAPE_PATH)
      raise ArgumentError, "#{provider}'s API index has no shape #{@shape}" unless SHAPES.include?(@shape)

      @reference = data["reference"]
      @source = data["source"]
      @reads = data.fetch("reads").map do |read|
        Read.new(call: read.fetch("call"), service: read["service"], purpose: read.fetch("purpose"), query: Array(read["query"]).map(&:to_s))
      end.freeze
      raise ArgumentError, "#{provider}'s API index lists #{@reads.size} reads, more than #{LIMIT}" if @reads.size > LIMIT
    end

    def name = IntegrationProvider.find(provider)&.name || provider.humanize

    # The index as the API skill's last steps.
    def text = [ HEADING, *reads.map { |read| "- #{line(read)}" } ].join("\n")

    def line(read)
      asked = read.query.any? ? " (#{read.query.join(', ')})" : ""
      "#{"#{read.service}: " if read.service}#{written(read)}#{asked}: #{read.purpose}"
    end

    def hint(tool_name, arguments)
      return nil unless tool_name.to_s == tool

      asked = asked(arguments.to_h.stringify_keys)
      return nil if asked.nil? || reads.any? { |read| listed?(read, asked) }

      nearest = nearest(asked).map { |read| "#{"#{read.service}: " if read.service}#{written(read)} (#{read.purpose.sub(/\.\z/, '')})" }
      "#{asked.words} is not among the key reads Firefight keeps for #{name}. The nearest are #{nearest.to_sentence}. The " \
        "#{skill} skill lists every key read, and when neither it nor the API reference lists one, #{name}'s API does not offer it."
    end

    # The reads nearest to what was asked, nearest first.
    def nearest(asked, count: NEAREST)
      reads.each_with_index.min_by(count) { |read, position| [ distance(read, asked), position ] }.map(&:first)
    end

    # What a call asked for, in the index's own terms: a verb and path's segments, an operation, or a query's field.
    Asked = Data.define(:verb, :service, :parts, :terms, :words)

    def asked(arguments)
      case shape
      when SHAPE_OPERATION
        operation = arguments["operation"].to_s.strip
        return nil if operation.empty?

        service = arguments["service"].to_s.strip.downcase.presence
        Asked.new(verb: nil, service: service, parts: [ folded(operation) ], terms: terms(operation), words: [ service, operation ].compact.join(" "))
      when SHAPE_GRAPHQL
        field = arguments[QUERY_FIELD].to_s[GRAPHQL_FIELD, 1]
        field && Asked.new(verb: nil, service: nil, parts: [ field.downcase ], terms: terms(field), words: "The query field #{field}")
      else
        path = arguments["path"].presence || arguments["code"].to_s[WRITTEN_PATH, 1]
        verb = (arguments["method"].presence || arguments["code"].to_s[WRITTEN_METHOD, 1]).to_s.upcase.presence || GET
        return nil if path.blank? || verb != GET

        service = arguments["service"].to_s.strip.downcase.presence
        Asked.new(verb: verb, service: service, parts: segments(path), terms: terms(path), words: "#{verb} #{path.to_s.split('?').first}")
      end
    end

    private

    def written(read) = shape == SHAPE_OPERATION ? read.call : read.call.sub(/\Aquery /, "")

    def listed?(read, asked)
      return false if asked.service && read.service && asked.service != read.service

      case shape
      when SHAPE_PATH
        template = segments(read.path)
        template.size == asked.parts.size && template.zip(asked.parts).all? { |segment, part| segment_pattern(segment).match?(part) }
      else
        read_parts(read) == asked.parts
      end
    end

    def read_parts(read)
      case shape
      when SHAPE_OPERATION then [ folded(read.call) ]
      when SHAPE_GRAPHQL then [ written(read).downcase ]
      else segments(read.path)
      end
    end

    def segments(path) = path.to_s.split("?").first.to_s.split("/").compact_blank

    def segment_pattern(segment) = /\A#{segment.split(PLACEHOLDER, -1).map { |part| Regexp.escape(part) }.join('[^/]+')}\z/

    # How far a read is from what was asked: an edit distance over the path's segments, where a placeholder matches any
    # segment and one segment differing from another costs by how far apart their letters are, less what their words
    # share, so /audit/logs finds /audit-logs and a wrong service costs a step.
    def distance(read, asked)
      ours = read_parts(read)
      cost = segment_distance(ours, asked.parts) - (0.5 * (terms(written(read)) & asked.terms).size)
      cost += 1 if asked.service && read.service && asked.service != read.service
      cost
    end

    def segment_distance(ours, theirs)
      row = (0..theirs.size).to_a
      ours.each_with_index do |segment, ours_index|
        previous = row.dup
        row[0] = ours_index + 1
        theirs.each_with_index do |part, theirs_index|
          row[theirs_index + 1] = [ previous[theirs_index + 1] + 1, row[theirs_index] + 1, previous[theirs_index] + apart(segment, part) ].min
        end
      end
      row.last
    end

    def apart(segment, part)
      return 0.0 if segment_pattern(segment).match?(part)

      ours = segment.gsub(PLACEHOLDER, "").downcase
      theirs = part.downcase
      return 0.3 if ours.length >= 3 && theirs.length >= 3 && (ours.include?(theirs) || theirs.include?(ours))

      letters(ours, theirs).to_f / [ ours.length, theirs.length, 1 ].max
    end

    def letters(ours, theirs)
      row = (0..theirs.length).to_a
      ours.each_char.with_index do |char, ours_index|
        previous = row.dup
        row[0] = ours_index + 1
        theirs.each_char.with_index do |other, theirs_index|
          row[theirs_index + 1] = [ previous[theirs_index + 1] + 1, row[theirs_index] + 1, previous[theirs_index] + (char == other ? 0 : 1) ].min
        end
      end
      row.last
    end

    def folded(name) = name.to_s.delete("_").downcase

    # The words a call is written with, placeholders left out, such as audit and logs of /v1/audit-logs or of ListAuditLogs.
    def terms(text)
      text.to_s.gsub(PLACEHOLDER, " ").gsub(/([a-z0-9])([A-Z])/, '\1 \2').downcase.split(/[^a-z0-9]+/).select { |word| word.length >= 3 }.uniq
    end
  end
end

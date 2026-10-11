module Integrations
  class ApiIndex
    # Keeps an index in step with the API reference the docs store holds (ProviderDocs::ApiDescription and the Northflank
    # client's endpoints), and the API skill's closing steps in step with the index. Each read's query parameters are
    # checked against the ones its reference lists, a fixed value such as Azure's api-version is taken from it, and a read
    # whose call the reference no longer lists is stale, which leaves the index as it is and names the call, since only a
    # person can choose what replaces it. A read listing no query parameters is given the reference's required ones and
    # the paging and filtering ones. An index taken from a provider's own site, with no reference in the store, only has
    # its skill written. bin/rails provider_docs:api_indexes runs it.
    class Refresh
      HEADING = /\A\#{2,3} (?<call>.+?)\s*\z/
      PARAMETER = /\A- (?<name>\S+) \((?<about>[^)]*)\)/
      GROUP = /\A(?<where>Query|Input|Argument):\z/
      INLINE_QUERY = /\AQuery: (?<names>.+?)\.?\z/
      REQUIRED = /(\A|, )required\z/
      ONE_OF = /one of (?<value>[^,]+)(, required)?\z/
      INDEX_PAGE = "/index.md".freeze
      # Query parameters that page or narrow a list, given to a read that names none, in the reference's order.
      KEY_PARAMETERS = %w[
        perpage page limit cursor after first pagesize pagelen maxresults nexttoken pagetoken status state environment ref
        branch since until from to starttime endtime start end event type filter
      ].freeze
      KEY_LIMIT = 5
      SKILL_FILES = Chat::Skill::DIRECTORY.join("*", "*", "*.md").to_s

      Section = Data.define(:parameters, :values)
      Result = Data.define(:index, :stale, :dropped, :changed) do
        def stale? = stale.any?
      end

      def self.all(write: true) = ApiIndex.all.map { |index| new(index).run(write: write) }

      # Each index's reads the reference in the store no longer lists, by provider, written nowhere. An index whose
      # reference the store does not hold yet is left out, since every read would look stale on a fresh install.
      def self.stale
        ApiIndex.all.select { |index| index.reference && held?(index) }.to_h { |index| [ index.provider, new(index).run(write: false).stale ] }
                .reject { |_provider, calls| calls.empty? }
      end

      def self.held?(index)
        ProviderDocPage.where(provider: index.provider).where("path LIKE ?", "#{ProviderDocPage.sanitize_sql_like(index.reference)}/%").exists?
      end
      private_class_method :held?

      def initialize(index)
        @index = index
      end

      # What the reference says of the index, written to its files unless write is false or a read is stale.
      def run(write: true)
        stale = []
        dropped = []
        reads = @index.reference ? @index.reads.map { |read| refreshed(read, stale, dropped) } : @index.reads
        yaml = Refresh.yaml(@index, reads)
        file = ApiIndex::DIRECTORY.join("#{@index.provider}.yml")
        skill_file, steps = skill_steps(ApiIndex.new(@index.provider, YAML.safe_load(yaml)))
        changed = []
        changed << file if File.read(file) != yaml
        changed << skill_file if File.read(skill_file) != steps
        if write && stale.empty?
          File.write(file, yaml) if changed.include?(file)
          File.write(skill_file, steps) if changed.include?(skill_file)
        end
        Result.new(index: @index, stale: stale, dropped: dropped, changed: changed)
      end

      # The index file as written: its reads in the order a person put them, each value plain where YAML reads it back
      # unchanged.
      def self.yaml(index, reads)
        lines = [
          "# #{index.name}'s key reads through #{index.tool}, at most #{ApiIndex::LIMIT}, which close the #{index.skill} skill",
          "# (Integrations::ApiIndex). Edit a read's call, purpose or query here, then run bin/rails provider_docs:api_indexes.",
          "tool: #{index.tool}",
          "skill: #{index.skill}"
        ]
        lines << "shape: #{index.shape}" unless index.shape == ApiIndex::SHAPE_PATH
        lines << "reference: #{scalar(index.reference)}" if index.reference
        lines << "source: #{scalar(index.source)}" if index.source
        lines << "reads:"
        reads.each do |read|
          lines << "  - call: #{scalar(read.call)}"
          lines << "    service: #{scalar(read.service)}" if read.service
          lines << "    purpose: #{scalar(read.purpose)}"
          lines << "    query: [ #{read.query.map { |name| flow_scalar(name) }.join(', ')} ]" if read.query.any?
        end
        "#{lines.join("\n")}\n"
      end

      def self.scalar(value)
        text = value.to_s
        plain = !text.match?(/\A[\s\[\]{}&*!|>'"%@`#,?:-]/) && !text.include?(": ") && !text.include?(" #") && !text.end_with?(":") &&
                YAML.safe_load("value: #{text}")&.dig("value") == text
        plain ? text : text.to_json
      rescue Psych::Exception
        text.to_json
      end

      # Inside a list written [ a, b ], brackets, braces and commas end a plain value, so a name such as page[size] is quoted.
      def self.flow_scalar(value) = value.to_s.match?(/[\[\]{},]/) ? value.to_s.to_json : scalar(value)

      private

      def refreshed(read, stale, dropped)
        section = sections(read.service)[read.call]
        if section.nil?
          stale << [ read.service, read.call ].compact.join(" ")
          return read
        end

        read.with(query: query_of(read, section, dropped))
      end

      def query_of(read, section, dropped)
        return chosen(section) if read.query.empty?

        given = read.query.filter_map do |each|
          name = each.split("=", 2).first
          unless section.parameters.include?(name)
            dropped << "#{read.call} #{name}"
            next
          end
          section.values[name] ? "#{name}=#{section.values[name]}" : each
        end
        # A value every call must send, such as Azure's api-version, is kept even where a person chose the rest.
        fixed = section.values.except(*given.map { |each| each.split("=", 2).first }).map { |name, value| "#{name}=#{value}" }
        given + fixed
      end

      def chosen(section)
        names = section.parameters.select do |name, required|
          required || KEY_PARAMETERS.include?(name.downcase.gsub(/[^a-z]/, ""))
        end.keys.first(KEY_LIMIT)
        names.map { |name| section.values[name] ? "#{name}=#{section.values[name]}" : name }
      end

      # Every read the reference details, by its call as headed there, each with its query parameters (name => whether
      # required) and the value a required parameter takes when it takes one only, such as Azure's api-version. A heading of an AWS operation names it with its
      # SDK name after it, so it is filed under both.
      def sections(service)
        @sections ||= {}
        @sections[service] ||= begin
          folder = [ @index.reference, service ].compact.join("/")
          pages = ProviderDocPage.where(provider: @index.provider).where("path LIKE ?", "#{ProviderDocPage.sanitize_sql_like(folder)}/%")
          pages.where.not("path LIKE ?", "%#{INDEX_PAGE}").order(:path).pluck(:content).each_with_object({}) do |content, found|
            parse(content.to_s.lines(chomp: true), found)
          end
        end
      end

      def parse(lines, found)
        current = nil
        where = nil
        lines.each do |line|
          if (heading = line.match(HEADING))
            current = { parameters: {}, values: {} }
            call = heading[:call]
            found[call] = current
            found[call.sub(/ \(\w+\)\z/, "")] = current
            where = nil
          elsif current.nil?
            next
          elsif (group = line.match(GROUP))
            where = group[:where]
          elsif (inline = line.match(INLINE_QUERY))
            inline[:names].split(",").map(&:strip).each { |name| current[:parameters][name] ||= false }
          elsif where && (parameter = line.match(PARAMETER))
            required = parameter[:about].match?(REQUIRED)
            current[:parameters][parameter[:name]] = required
            value = parameter[:about][ONE_OF, :value]
            current[:values][parameter[:name]] = value.strip if required && value
          elsif line.strip.empty? || line.start_with?("Answers:")
            where = nil if line.start_with?("Answers:")
          else
            where = nil unless line.start_with?("- ")
          end
        end
        found.transform_values! { |each| each.is_a?(Hash) ? Section.new(parameters: each[:parameters], values: each[:values]) : each }
      end

      # Every skill's file and words, by its provider and name.
      def skill_files
        Dir[SKILL_FILES].sort.each_with_object({}) do |path, found|
          written = File.read(path)
          header = written[Chat::Skill::FRONT_MATTER, 1]
          next unless header

          found[[ Pathname(path).relative_path_from(Chat::Skill::DIRECTORY).each_filename.first, YAML.safe_load(header)["name"] ]] = [ path, written ]
        end
      end

      def skill_steps(index)
        file, written = skill_files[[ index.provider, index.skill ]]
        raise ArgumentError, "#{index.provider}'s API index closes the #{index.skill} skill, which does not exist" unless file

        kept = written.split("\n#{ApiIndex::HEADING}\n", 2).first.split("\n#{ApiIndex::HEADING}", 2).first.rstrip
        [ file, "#{kept}\n\n#{index.text}\n" ]
      end
    end
  end
end

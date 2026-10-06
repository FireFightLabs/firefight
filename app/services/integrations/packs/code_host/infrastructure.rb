module Integrations
  module Packs
    module CodeHost
      # The infrastructure defined as code in the repositories a connection sees, read through the code host's API so no
      # code is run or checked out: Terraform, Pulumi and CDK projects, Helm charts and Kubernetes manifests, and the config
      # files of the platforms that deploy from a repository. Only these files are read, each within a size cap, and only
      # into memory. What was left unread is said in the gaps, and only a repository read in full can take a suggestion
      # away. A host's subclass lists a repository's files (listing), reads one (content) and links to it (url), and takes
      # repositories as full_name, default_branch, size, archived and fork.
      class Infrastructure
        # provider is the code host the repository is on, so the same path on two hosts is never taken for one repository.
        File = Data.define(:repository, :path, :tool, :content, :url, :provider)
        # A file in a repository's listing. size is nil when the host does not say it before the file is read.
        Entry = Data.define(:path, :size, :id)
        Listing = Data.define(:entries, :truncated)
        # Raised by content for a file the host only said was too large once asked for it.
        class TooLarge < StandardError; end

        TERRAFORM = "Terraform".freeze
        PULUMI = "Pulumi".freeze
        CDK = "CDK".freeze
        HELM = "Helm".freeze
        KUBERNETES = "Kubernetes".freeze
        WRANGLER = "Wrangler".freeze
        FLY = "Fly".freeze
        RENDER = "Render".freeze
        VERCEL = "Vercel".freeze
        SERVERLESS = "Serverless".freeze
        NETLIFY = "Netlify".freeze
        # Files that are infrastructure wherever they sit, by name or extension.
        BY_NAME = {
          /\.tf(\.json)?\z/ => TERRAFORM, %r{(\A|/)terragrunt\.hcl\z} => TERRAFORM,
          %r{(\A|/)wrangler\.(toml|json|jsonc)\z} => WRANGLER, %r{(\A|/)fly\.toml\z} => FLY, %r{(\A|/)render\.ya?ml\z} => RENDER,
          %r{(\A|/)vercel\.json\z} => VERCEL, %r{(\A|/)serverless\.ya?ml\z} => SERVERLESS, %r{(\A|/)netlify\.toml\z} => NETLIFY,
          %r{(\A|/)kustomization\.ya?ml\z} => KUBERNETES
        }.freeze
        # A directory holding one of these is a project. A chart's YAML is all infrastructure, a program's only its entry
        # files, so the application code beside a cdk.json is never read as infrastructure.
        PROJECT_MARKERS = { "Pulumi.yaml" => PULUMI, "Pulumi.yml" => PULUMI, "cdk.json" => CDK, "Chart.yaml" => HELM }.freeze
        PROGRAM_FILES = %r{\A((index|main|__main__|app|Program)\.(ts|js|py|go|cs|java)|(bin|lib|stacks|infra|infrastructure)/.+\.(ts|js|py|go|cs|java)|Pulumi\.ya?ml|cdk\.json)\z}
        CHART_FILES = /\.ya?ml\z/
        # Directories whose YAML is taken as Kubernetes manifests when it says so.
        MANIFEST_DIRECTORIES = %r{(\A|/)(k8s|kubernetes|manifests|deploy|deployment|kustomize|overlays|base)(/|\z)}
        SKIPPED = %r{(\A|/)(node_modules|vendor|\.terraform|dist|build|\.git)/}
        # Never read, since they hold values rather than names: a Secret manifest, and a Pulumi stack's own config.
        SECRET_MANIFEST = /^kind:\s*Secret\s*$/
        STACK_CONFIG = %r{(\A|/)Pulumi\.[^/]+\.ya?ml\z}
        MAX_REPOSITORIES = 200
        MAX_FILES = 500
        MAX_FILE_BYTES = 200_000
        # A changed path that may be an infrastructure file, judged from the path alone, as a push names it. A chart's YAML
        # counts under a charts or helm directory, and a Pulumi or CDK program's files under a directory named for
        # infrastructure, since without the repository's listing nothing else says which directory is a project.
        CHANGED_CHART = %r{(\A|/)(charts?|helm)/.+\.ya?ml\z}
        CHANGED_PROGRAM = %r{(\A|/)(infra|infrastructure|stacks|cdk|pulumi)/.+\.(ts|js|py|go|cs|java)\z}

        # Whether a change to path may change what the files say, so a push that changes one is read again.
        def self.defines?(path)
          path = path.to_s
          return false if path.match?(SKIPPED) || path.match?(STACK_CONFIG)

          BY_NAME.keys.any? { |pattern| path.match?(pattern) } || PROJECT_MARKERS.key?(::File.basename(path)) ||
            (path.match?(/\.ya?ml\z/) && path.match?(MANIFEST_DIRECTORIES)) || path.match?(CHANGED_CHART) || path.match?(CHANGED_PROGRAM)
        end

        attr_reader :gaps, :read_in_full

        def initialize
          @gaps = []
          @read_in_full = []
        end

        def files(repositories)
          read = []
          searched = repositories.reject { |repository| repository["archived"] || repository["fork"] }
          @gaps << "Only #{MAX_REPOSITORIES} repositories were searched for infrastructure files." if searched.size > MAX_REPOSITORIES
          searched.first(MAX_REPOSITORIES).each_with_index do |repository, index|
            if read.size >= MAX_FILES
              cut_short("the first #{MAX_FILES} infrastructure files were read")
              break
            end
            read.concat(repository_files(repository, MAX_FILES - read.size))
          rescue Integrations::RateLimited
            cut_short("#{self.class::HOST}'s rate limit was reached after #{index} of #{[ searched.size, MAX_REPOSITORIES ].min} repositories")
            break
          end
          read
        end

        private

        def provider = self.class::PROVIDER

        def cut_short(why)
          @gaps << "Not every repository was searched for infrastructure files, since #{why}."
        end

        def repository_files(repository, room)
          name = repository["full_name"]
          branch = repository["default_branch"]
          if branch.blank? || repository["size"].to_i.zero?
            @read_in_full << name
            return []
          end

          listed = listing(repository)
          candidates, too_large = candidates(listed.entries)
          files, failed, refused = read_files(repository, candidates.first(room))
          too_large += refused
          gap(name, listed.truncated, too_large, failed, candidates.size > room)
          @read_in_full << name unless listed.truncated || too_large.positive? || failed.any? || candidates.size > room
          files
        rescue Integrations::RateLimited
          raise
        rescue self.class::FAILED => error
          @gaps << Sentence.join("The files of #{name} could not be listed", error)
          []
        end

        def candidates(entries)
          blobs = entries.reject { |entry| entry.path.match?(SKIPPED) || entry.path.match?(STACK_CONFIG) }
          projects = blobs.filter_map do |entry|
            tool = PROJECT_MARKERS[::File.basename(entry.path)]
            [ ::File.dirname(entry.path), tool ] if tool
          end
          wanted = blobs.filter_map { |entry| [ entry, kind_of(entry.path, projects) ] }.select(&:last)
          too_large = wanted.count { |entry, _| entry.size.to_i > MAX_FILE_BYTES }
          [ wanted.reject { |entry, _| entry.size.to_i > MAX_FILE_BYTES }, too_large ]
        end

        def kind_of(path, projects)
          BY_NAME.find { |pattern, _| path.match?(pattern) }&.last || project_tool(path, projects) ||
            (KUBERNETES if path.match?(/\.ya?ml\z/) && path.match?(MANIFEST_DIRECTORIES))
        end

        def project_tool(path, projects)
          projects.each do |directory, tool|
            inside = directory == "." ? path : (path.delete_prefix("#{directory}/") if path.start_with?("#{directory}/"))
            next unless inside

            return tool if tool == HELM ? inside.match?(CHART_FILES) : inside.match?(PROGRAM_FILES)
          end
          nil
        end

        def read_files(repository, candidates)
          failed = []
          refused = 0
          files = candidates.filter_map do |entry, tool|
            file(repository, entry, tool)
          rescue TooLarge
            refused += 1
            nil
          rescue Integrations::RateLimited
            raise
          rescue self.class::FAILED => error
            failed << error.message
            nil
          end
          [ files, failed, refused ]
        end

        def file(repository, entry, tool)
          name = repository["full_name"]
          path = entry.path
          content = content(repository, entry).to_s.dup.force_encoding(Encoding::UTF_8).scrub
          return if content.match?(SECRET_MANIFEST)
          # A YAML file in a manifest directory is only a manifest when it says what kind of object it is.
          return if tool == KUBERNETES && !path.include?("kustomization") && !content.match?(/^kind:\s*\S/)

          File.new(repository: name, path: path, tool: tool, content: content, url: url(repository, path), provider: provider)
        end

        # Each segment escaped, so a space or a hash in a file name still opens the file.
        def escaped_path(path) = path.split("/").map { |part| Http.segment(part) }.join("/")

        def gap(name, truncated, too_large, failed, cut)
          @gaps << "#{name} is too large to list in full, so some of its infrastructure files may be missing." if truncated
          @gaps << "#{too_large} infrastructure #{'file'.pluralize(too_large)} in #{name} #{too_large == 1 ? 'is' : 'are'} over #{MAX_FILE_BYTES / 1000} KB and #{too_large == 1 ? 'was' : 'were'} not read." if too_large.positive?
          @gaps << Sentence.join("#{failed.size} infrastructure #{'file'.pluralize(failed.size)} in #{name} could not be read", failed.first) if failed.any?
          @gaps << "Not every infrastructure file in #{name} was read, since the first #{MAX_FILES} across all repositories were." if cut
        end
      end
    end
  end
end

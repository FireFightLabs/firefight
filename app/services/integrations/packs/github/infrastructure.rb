module Integrations
  module Packs
    class Github
      # The infrastructure defined as code in the repositories a connection sees, read through GitHub's API so no code is
      # run or checked out: Terraform, Pulumi and CDK projects, Helm charts and Kubernetes manifests, and the config files
      # of the platforms that deploy from a repository. Only these files are read, each within a size cap, and only into
      # memory. What was left unread is said in the gaps, and only a repository read in full can take a suggestion away.
      class Infrastructure
        File = Data.define(:repository, :path, :tool, :content, :url)

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

        attr_reader :gaps, :read_in_full

        def initialize(token)
          @token = token
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
          rescue GithubApp::RateLimited
            cut_short("GitHub's rate limit was reached after #{index} of #{[ searched.size, MAX_REPOSITORIES ].min} repositories")
            break
          end
          read
        end

        private

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

          tree = GithubApp.get("/repos/#{name}/git/trees/#{ERB::Util.url_encode(branch)}?recursive=1", token: @token)
          candidates, too_large = candidates(tree)
          files, failed = read_files(repository, candidates.first(room))
          gap(name, tree["truncated"], too_large, failed, candidates.size > room)
          @read_in_full << name unless tree["truncated"] || too_large.positive? || failed.any? || candidates.size > room
          files
        rescue GithubApp::RateLimited
          raise
        rescue GithubApp::Error => error
          @gaps << Sentence.join("The files of #{name} could not be listed", error)
          []
        end

        def candidates(tree)
          blobs = Array(tree["tree"]).select { |entry| entry["type"] == "blob" && !entry["path"].match?(SKIPPED) && !entry["path"].match?(STACK_CONFIG) }
          projects = blobs.filter_map do |entry|
            tool = PROJECT_MARKERS[::File.basename(entry["path"])]
            [ ::File.dirname(entry["path"]), tool ] if tool
          end
          wanted = blobs.filter_map { |entry| [ entry, kind_of(entry["path"], projects) ] }.select(&:last)
          too_large = wanted.count { |entry, _| entry["size"].to_i > MAX_FILE_BYTES }
          [ wanted.reject { |entry, _| entry["size"].to_i > MAX_FILE_BYTES }, too_large ]
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
          files = candidates.filter_map do |entry, tool|
            file(repository, entry, tool)
          rescue GithubApp::RateLimited
            raise
          rescue GithubApp::Error => error
            failed << error.message
            nil
          end
          [ files, failed ]
        end

        def file(repository, entry, tool)
          name = repository["full_name"]
          path = entry["path"]
          blob = GithubApp.get("/repos/#{name}/git/blobs/#{entry['sha']}", token: @token)
          content = blob["encoding"] == "base64" ? Base64.decode64(blob["content"].to_s) : blob["content"].to_s
          content = content.force_encoding(Encoding::UTF_8).scrub
          return if content.match?(SECRET_MANIFEST)
          # A YAML file in a manifest directory is only a manifest when it says what kind of object it is.
          return if tool == KUBERNETES && !path.include?("kustomization") && !content.match?(/^kind:\s*\S/)

          File.new(repository: name, path: path, tool: tool, content: content,
                   url: "https://github.com/#{name}/blob/#{ERB::Util.url_encode(repository['default_branch'])}/#{path.split('/').map { |part| ERB::Util.url_encode(part) }.join('/')}")
        end

        def gap(name, truncated, too_large, failed, cut)
          @gaps << "#{name} is too large to list in full, so some of its infrastructure files may be missing." if truncated
          @gaps << "#{too_large} infrastructure #{'file'.pluralize(too_large)} in #{name} #{too_large == 1 ? 'is' : 'are'} over #{MAX_FILE_BYTES / 1000} KB and #{too_large == 1 ? 'was' : 'were'} not read." if too_large.positive?
          @gaps << "#{failed.size} infrastructure #{'file'.pluralize(failed.size)} in #{name} could not be read: #{failed.first}" if failed.any?
          @gaps << "Not every infrastructure file in #{name} was read, since the first #{MAX_FILES} across all repositories were." if cut
        end
      end
    end
  end
end

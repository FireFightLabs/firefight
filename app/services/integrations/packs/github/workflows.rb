module Integrations
  module Packs
    class Github
      # A repository's setup read from its GitHub Actions workflows, for Integrations::CiSetup. The job that runs its
      # tests is the one with the most services, then one whose steps run tests. Its services keep their images, ports
      # and variables, the workflow's, the job's and its steps' variables are kept, and its run steps before the tests
      # are the commands. A step that uses an action is left out, since the sandbox installs what the lockfiles and
      # version files ask for itself.
      module Workflows
        DIRECTORY = ".github/workflows".freeze
        FILE = /\.ya?ml\z/
        EXPRESSION = /\$\{\{/
        FILE_LIMIT = 20
        LEFT_OUT_ACTIONS = "using an action, such as actions/setup-node, since the sandbox installs what the lockfiles and version files ask for".freeze

        def ci_setup(environment_row, repository:)
          repo = repo_argument({ "repo" => repository.to_s })
          token = GithubApp.installation_token(environment_row)
          notes = []
          jobs = ci_paths(repo, token).flat_map do |path|
            workflow, unreadable = CiSetup.yaml(Base64.decode64(GithubApp.get("/repos/#{repo}/contents/#{path}", token: token)["content"].to_s))
            notes << "Could not read #{path}: #{unreadable}." if unreadable
            ci_jobs(path, workflow)
          end
          chosen = jobs.select { |job| ci_run_steps(job[:job]).any? }.each_with_index.max_by { |job, index| [ ci_score(job[:job]), -index ] }&.first
          raise CiSetup::Missing, "#{repo} has no workflow in #{DIRECTORY} with a job that runs commands." unless chosen

          ci_setup_of(chosen, notes)
        end

        private

        def ci_paths(repo, token)
          listed = GithubApp.get("/repos/#{repo}/contents/#{DIRECTORY}", token: token)
          Array(listed).select { |entry| entry.is_a?(Hash) && entry["type"] == "file" && entry["name"].to_s.match?(FILE) }.map { |entry| entry["path"] }.first(FILE_LIMIT)
        rescue GithubApp::NotFound
          raise CiSetup::Missing, "#{repo} has no #{DIRECTORY} folder."
        end

        def ci_jobs(path, workflow)
          return [] unless workflow.is_a?(Hash) && workflow["jobs"].is_a?(Hash)

          workflow["jobs"].filter_map do |key, job|
            next unless job.is_a?(Hash) && job["steps"].is_a?(Array)

            name = job["name"].is_a?(String) && !job["name"].match?(EXPRESSION) ? job["name"] : key.to_s
            { path: path, name: name, env: ci_hash(workflow["env"]), job: job }
          end
        end

        def ci_score(job)
          (ci_services(job).size * 10) + (ci_run_steps(job).any? { |step| step["run"].to_s.match?(CiSetup::TEST_COMMAND) } ? 1 : 0)
        end

        def ci_run_steps(job) = job["steps"].select { |step| step.is_a?(Hash) && step["run"].is_a?(String) }

        def ci_setup_of(chosen, notes)
          job = chosen[:job]
          services = ci_services(job)
          kept_services = services.filter_map { |key, spec| ci_service(key, spec, notes) }
          steps = job["steps"].select { |step| step.is_a?(Hash) }
          actions = steps.count { |step| step["uses"] }
          plain, filled = ci_run_steps(job).partition { |step| !step["run"].match?(EXPRESSION) }
          directory = job.dig("defaults", "run", "working-directory")
          commands = plain.map { |step| ci_command(step["working-directory"] || directory, step["run"]) }
          env = ci_hash(chosen[:env]).merge(ci_hash(job["env"]), *plain.map { |step| ci_hash(step["env"]) })
          hosts = job["container"] ? services.keys.map(&:to_s) : []
          said = [ (CiSetup.steps_left_out(actions, LEFT_OUT_ACTIONS) if actions.positive?),
                   CiSetup.steps_left_out(filled.size, "using GitHub expressions, which only GitHub fills in"),
                   ("This job runs in a container and reaches its services by name, so here they are reached on #{CiSetup::LOCALHOST}." if hosts.any?) ]
          CiSetup.found(services: kept_services, env: env, commands: commands, source: "#{chosen[:path]}, job #{chosen[:name]}",
                        expression: ->(value) { value.match?(EXPRESSION) }, hosts: hosts, notes: notes + said.compact)
        end

        def ci_service(key, spec, notes)
          spec = { "image" => spec } if spec.is_a?(String)
          image = spec.is_a?(Hash) ? spec["image"].to_s : ""
          if image.empty? || image.match?(EXPRESSION)
            notes << "Left out the #{key} service, whose image only GitHub fills in."
            return
          end

          { "name" => CiSetup.service_name(image, key), "image" => image, "port" => ci_port(spec["ports"]), "env" => ci_hash(spec["env"]) }.compact
        end

        # The port the job reaches a service on, from a mapping such as 5432:5432. A port alone is mapped to one GitHub
        # picks, so the service keeps its usual one.
        def ci_port(ports)
          mapping = Array(ports).map(&:to_s).find { |port| port.include?(":") }
          mapping && Integer(mapping.split(":").first, exception: false)
        end

        def ci_command(directory, command)
          return command.strip if directory.blank? || directory.to_s.match?(EXPRESSION)

          "cd #{Shellwords.escape(directory.to_s)}\n#{command.strip}"
        end

        def ci_services(job) = job["services"].is_a?(Hash) ? job["services"] : {}

        def ci_hash(value) = value.is_a?(Hash) ? value.to_h { |key, each| [ key.to_s, each.to_s ] } : {}
      end
    end
  end
end

module Integrations
  module Packs
    class AzureDevops
      # A repository's setup read from its azure-pipelines.yml, for Integrations::CiSetup, in the shape Azure Pipelines'
      # YAML schema gives it (learn.microsoft.com/azure/devops/pipelines/yaml-schema): a pipeline of steps, of jobs, or of
      # stages holding jobs. The job that runs its tests is the one with the most services, then one whose script runs
      # tests. Its services are the container resources its services name (resources.containers, container and image,
      # with their env), the pipeline's, stage's and job's variables are kept with references to each other filled in,
      # and its script, bash and pwsh lines before the tests are the commands. A job runs each step in a shell of its own.
      # Azure Pipelines reaches a service by its name from a job that runs in a container and on localhost otherwise
      # (Service containers), which here is the box itself.
      module CiConfig
        FILE = "azure-pipelines.yml".freeze
        SCRIPT_KEYS = %w[script bash pwsh powershell].freeze
        # A variable Azure Pipelines fills in, as $(name) at runtime.
        REFERENCE = /\$\(([A-Za-z_][A-Za-z0-9_.]*)\)/
        TEMPLATE = /\$\{\{.*?\}\}|\$\[.*?\]/

        def ci_setup(environment_row, repository:)
          repo = repo_argument({ "repo" => repository.to_s })
          azure = api(environment_row)
          text = begin
            azure.get("#{path_of(repo)}/items", "path" => "/#{FILE}", "includeContent" => true, "$format" => "json")["content"].to_s
          rescue AzureDevopsApi::NotFound
            raise CiSetup::Missing, "#{repo} has no #{FILE} at its root."
          end
          config, unreadable = CiSetup.yaml(text)
          raise CiSetup::Missing, "Could not read #{repo}'s #{FILE}: #{unreadable}." if unreadable
          raise CiSetup::Missing, "#{repo}'s #{FILE} has no jobs." unless config.is_a?(Hash)

          jobs = ci_jobs(config).select { |job, _variables| ci_lines(job).any? }
          chosen, variables = jobs.each_with_index.max_by { |(job, _variables), index| [ ci_score(job), -index ] }&.first
          raise CiSetup::Missing, "#{repo}'s #{FILE} has no job with a script." unless chosen

          ci_setup_of(config, chosen, variables)
        end

        private

        # Every job with the variables the pipeline and its stage give it, a pipeline of steps alone being one job.
        def ci_jobs(config)
          top = ci_variables(config["variables"])
          return [ [ config, top ] ] if config["steps"].is_a?(Array)

          stages = Array(config["stages"]).select { |stage| stage.is_a?(Hash) }
          from_stages = stages.flat_map do |stage|
            Array(stage["jobs"]).select { |job| job.is_a?(Hash) }.map { |job| [ job, top.merge(ci_variables(stage["variables"])) ] }
          end
          from_stages + Array(config["jobs"]).select { |job| job.is_a?(Hash) }.map { |job| [ job, top ] }
        end

        def ci_score(job) = (ci_services(job).size * 10) + (ci_lines(job).any? { |line| line.match?(CiSetup::TEST_COMMAND) } ? 1 : 0)

        def ci_services(job) = job["services"].is_a?(Hash) ? job["services"] : {}

        def ci_lines(job)
          Array(job["steps"]).select { |step| step.is_a?(Hash) }.flat_map do |step|
            SCRIPT_KEYS.filter_map { |key| step[key] if step[key].is_a?(String) }.flat_map { |script| script.lines.map(&:strip) }
          end.compact_blank
        end

        def ci_setup_of(config, job, variables)
          containers = Array(config.dig("resources", "containers")).select { |container| container.is_a?(Hash) }.index_by { |container| container["container"].to_s }
          variables = variables.merge(ci_variables(job["variables"]))
          services = ci_services(job).filter_map do |name, alias_name|
            container = containers[alias_name.to_s] || {}
            image = container["image"].to_s.presence
            next unless image

            env = container["env"].is_a?(Hash) ? container["env"].to_h { |key, value| [ key.to_s, value.to_s ] } : {}
            { "name" => CiSetup.service_name(image, name.to_s), "image" => image, "env" => ci_filled(variables.merge(env)) }
          end
          hosts = ci_services(job).keys.map(&:to_s)
          notes = []
          notes << "Left out what #{FILE} takes from templates, which Halon does not read." if config.key?("extends") || ci_templates?(config, job)
          notes << "Azure Pipelines reaches this job's services at #{hosts.to_sentence} from a container job, so here they are reached on #{CiSetup::LOCALHOST}." if hosts.any?
          name = job["job"].to_s.presence || job["displayName"].to_s.presence || "the pipeline's steps"
          CiSetup.found(services: services, env: ci_filled(variables), commands: ci_lines(job), source: "#{FILE}, job #{name}",
                        expression: ->(value) { value.match?(REFERENCE) || value.match?(TEMPLATE) }, hosts: hosts, notes: notes)
        end

        def ci_templates?(config, job) = [ config, job ].any? { |each| Array(each["steps"]).any? { |step| step.is_a?(Hash) && step.key?("template") } }

        # Variables as a mapping, or as a list of name and value, where a group's or a template's are left out.
        def ci_variables(value)
          case value
          when Hash then value.to_h { |key, each| [ key.to_s, each.to_s ] }
          when Array then value.select { |each| each.is_a?(Hash) && each["name"].present? }.to_h { |each| [ each["name"].to_s, each["value"].to_s ] }
          else {}
          end
        end

        # Variables with references to each other filled in, as Azure Pipelines does. One that names a variable only the
        # pipeline knows keeps its reference and is left out later.
        def ci_filled(variables)
          variables.transform_values do |value|
            value.gsub(REFERENCE) { |reference| (known = variables[Regexp.last_match(1)]) && !known.match?(REFERENCE) ? known : reference }
          end
        end
      end
    end
  end
end

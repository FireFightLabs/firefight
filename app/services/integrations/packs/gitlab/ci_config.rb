module Integrations
  module Packs
    class Gitlab
      # A project's setup read from its .gitlab-ci.yml, for Integrations::CiSetup. The job that runs its tests is the
      # one with the most services, then one whose script runs tests, after what it extends in the same file. Its
      # services keep their images, aliases and variables, the file's and the job's variables are kept with references
      # to each other filled in, and its before_script and script lines before the tests are the commands, kept in one
      # shell as GitLab runs them. GitLab reaches a service at a host named after its image or its alias, which here is
      # the box itself.
      module CiConfig
        FILE = ".gitlab-ci.yml".freeze
        KEYWORDS = %w[stages variables default include workflow image services before_script after_script cache spec].freeze
        # A variable GitLab fills in, such as $CI_COMMIT_SHA or ${DB_PASSWORD} from the project's settings.
        REFERENCE = /\$(?:\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))/
        EXTENDS_DEPTH = 10

        def ci_setup(environment_row, repository:)
          repo = repo_argument({ "repo" => repository.to_s })
          text = begin
            api(environment_row).text("#{GitlabApi.file(repo, FILE)}/raw", "ref" => HEAD)
          rescue GitlabApi::NotFound
            raise CiSetup::Missing, "#{repo} has no #{FILE}."
          end
          config, unreadable = CiSetup.yaml(text)
          raise CiSetup::Missing, "Could not read #{repo}'s #{FILE}: #{unreadable}." if unreadable
          raise CiSetup::Missing, "#{repo}'s #{FILE} has no jobs." unless config.is_a?(Hash)

          jobs = config.filter_map do |name, job|
            next if KEYWORDS.include?(name.to_s) || name.to_s.start_with?(".") || !job.is_a?(Hash)

            merged = ci_extended(config, job)
            [ name.to_s, merged ] if Array(merged["script"]).any?
          end
          name, job = jobs.each_with_index.max_by { |(_name, each), index| [ ci_score(each, config), -index ] }&.first
          raise CiSetup::Missing, "#{repo}'s #{FILE} has no job with a script." unless job

          ci_setup_of(config, name, job)
        end

        private

        # What a job extends from hidden jobs in the same file, merged as GitLab merges it: hashes key by key, lists replaced.
        def ci_extended(config, job, depth = 0)
          parents = Array(job["extends"]).filter_map { |parent| config[parent.to_s] if config[parent.to_s].is_a?(Hash) }
          return job if parents.empty? || depth > EXTENDS_DEPTH

          merged = parents.map { |parent| ci_extended(config, parent, depth + 1) }.reduce({}) { |all, parent| all.deep_merge(parent) }
          merged.deep_merge(job.except("extends"))
        end

        def ci_job_services(job, config)
          defaults = config["default"].is_a?(Hash) ? config["default"] : {}
          Array(job["services"] || defaults["services"] || config["services"]).filter_map do |service|
            service = { "name" => service } if service.is_a?(String)
            service if service.is_a?(Hash) && service["name"].is_a?(String)
          end
        end

        def ci_score(job, config)
          (ci_job_services(job, config).size * 10) + (ci_lines(job["script"]).any? { |line| line.match?(CiSetup::TEST_COMMAND) } ? 1 : 0)
        end

        def ci_lines(value) = Array(value).flatten.filter_map { |line| line.to_s.strip.presence if line.is_a?(String) }

        def ci_setup_of(config, name, job)
          defaults = config["default"].is_a?(Hash) ? config["default"] : {}
          services = ci_job_services(job, config)
          hosts = services.flat_map { |service| ci_hosts(service) }.uniq
          variables = ci_variables(config["variables"]).merge(ci_variables(job["variables"]))
          before = job.key?("before_script") ? job["before_script"] : (defaults["before_script"] || config["before_script"])
          kept = services.map do |service|
            { "name" => CiSetup.service_name(service["name"]), "image" => service["name"], "env" => ci_filled(variables.merge(ci_variables(service["variables"]))) }
          end
          notes = []
          notes << "Left out what #{FILE} includes from other files, which Halon does not read." if config["include"]
          notes << "GitLab reaches this job's services at #{hosts.to_sentence}, so here they are reached on #{CiSetup::LOCALHOST}." if hosts.any?
          CiSetup.found(services: kept, env: ci_filled(variables), commands: ci_lines(before) + ci_lines(job["script"]), source: "#{FILE}, job #{name}",
                        expression: ->(value) { value.match?(REFERENCE) }, hosts: hosts, notes: notes, one_shell: true)
        end

        # The hosts GitLab gives a service: its alias, and its image's name with the tag left out and each slash as a
        # dash and as two underscores (Services, Accessing the services, in GitLab's CI docs).
        def ci_hosts(service)
          image = service["name"].split("@").first.sub(/:[^\/:]+\z/, "")
          [ *service["alias"].to_s.split(/[\s,]+/), image.tr("/", "-"), image.gsub("/", "__") ].compact_blank.uniq
        end

        def ci_variables(value)
          return {} unless value.is_a?(Hash)

          value.to_h { |key, each| [ key.to_s, (each.is_a?(Hash) ? each["value"] : each).to_s ] }
        end

        # Variables with references to each other filled in, as GitLab does. One that names a variable only GitLab knows
        # keeps its reference and is left out later.
        def ci_filled(variables)
          variables.transform_values do |value|
            value.gsub(REFERENCE) { |reference| (known = variables[Regexp.last_match(1) || Regexp.last_match(2)]) && !known.match?(REFERENCE) ? known : reference }
          end
        end
      end
    end
  end
end

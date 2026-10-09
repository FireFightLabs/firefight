module Integrations
  module Packs
    class Bitbucket
      # A repository's setup read from its bitbucket-pipelines.yml, for Integrations::CiSetup. The step that runs its
      # tests is the one with the most services, then one whose script runs tests, among the default pipeline, the pull
      # request pipelines and the branch pipelines. Its services are the ones definitions names for it, with their
      # images and variables, and its script lines before the tests are the commands, kept in one shell as Bitbucket
      # runs them. Bitbucket runs a step's services beside it on localhost, as the sandbox does.
      module CiConfig
        FILE = "bitbucket-pipelines.yml".freeze
        PIPELINES = %w[default pull-requests branches tags custom].freeze
        # Bitbucket's own service for building images, which the sandbox has no use for.
        DOCKER = "docker".freeze
        REFERENCE = /\$(?:\{[A-Za-z_][A-Za-z0-9_]*\}|[A-Za-z_][A-Za-z0-9_]*)/

        def ci_setup(environment_row, repository:)
          repo = repo_argument({ "repo" => repository.to_s })
          bitbucket = api(environment_row)
          text = begin
            bitbucket.text("#{BitbucketApi.repository(repo)}/src/#{commit_of(bitbucket, repo, nil)}/#{FILE}")
          rescue BitbucketApi::NotFound
            raise CiSetup::Missing, "#{repo} has no #{FILE}."
          end
          config, unreadable = CiSetup.yaml(text)
          raise CiSetup::Missing, "Could not read #{repo}'s #{FILE}: #{unreadable}." if unreadable

          steps = ci_steps(config.is_a?(Hash) ? config["pipelines"] : nil)
          step = steps.each_with_index.max_by { |each, index| [ ci_score(each), -index ] }&.first
          raise CiSetup::Missing, "#{repo}'s #{FILE} has no step with a script." unless step

          ci_setup_of(config, step)
        end

        private

        # Every step with a script, in the order the pipelines list them, inside parallel groups and stages too.
        def ci_steps(pipelines)
          return [] unless pipelines.is_a?(Hash)

          PIPELINES.flat_map do |kind|
            pipeline = pipelines[kind]
            pipeline.is_a?(Hash) ? pipeline.values.flat_map { |each| ci_entries(each) } : ci_entries(pipeline)
          end.select { |step| Array(step["script"]).any? }
        end

        def ci_entries(value)
          case value
          when Array then value.flat_map { |each| ci_entries(each) }
          when Hash
            return [ value["step"] ] if value["step"].is_a?(Hash)

            ci_entries(value["parallel"].is_a?(Hash) ? value["parallel"]["steps"] : value["parallel"]) +
              ci_entries(value["stage"].is_a?(Hash) ? value["stage"]["steps"] : nil) + ci_entries(value["steps"])
          else []
          end
        end

        def ci_score(step)
          services = Array(step["services"]).count { |name| name.to_s != DOCKER }
          (services * 10) + (ci_lines(step).any? { |line| line.match?(CiSetup::TEST_COMMAND) } ? 1 : 0)
        end

        def ci_lines(step) = Array(step["script"]).flatten.filter_map { |line| line.to_s.strip.presence if line.is_a?(String) }

        def ci_setup_of(config, step)
          definitions = config.dig("definitions", "services")
          definitions = {} unless definitions.is_a?(Hash)
          services = Array(step["services"]).map(&:to_s).reject { |name| name == DOCKER }.map do |name|
            definition = definitions[name].is_a?(Hash) ? definitions[name] : {}
            variables = definition["variables"].is_a?(Hash) ? definition["variables"].to_h { |key, value| [ key.to_s, value.to_s ] } : {}
            { "name" => CiSetup.service_name(definition["image"], name), "image" => definition["image"].to_s.presence, "env" => variables }.compact
          end
          pipes = Array(step["script"]).count { |line| line.is_a?(Hash) && line["pipe"] }
          name = step["name"].to_s.presence || "unnamed"
          CiSetup.found(services: services, env: {}, commands: ci_lines(step), source: "#{FILE}, step #{name}",
                        expression: ->(value) { value.match?(REFERENCE) }, notes: [ CiSetup.steps_left_out(pipes, "running a pipe, which only Bitbucket runs") ].compact,
                        one_shell: true)
        end
      end
    end
  end
end

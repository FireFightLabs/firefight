module Integrations
  module Packs
    class Bitbucket
      # A repository's deployments read as runs, deploying an earlier one again, and its tags (the deployments, pipelines
      # and refs/tags paths of Bitbucket's OpenAPI description). A deployment names the release a pipeline made, its
      # commit and that pipeline's results page (release.url), so deploying it again finds that pipeline among the ones
      # built on the commit (pipelines filtered by target.commit.hash) and starts it again on the same target and
      # definition, as rerun_pipeline does. Bitbucket's API cannot start a manual step, so a deployment step a person
      # starts by hand still waits for them.
      module Deployments
        RESULTS_NUMBER = %r{/pipelines/results/(\d+)}
        TAG_LIMIT = 20
        MAX_TAGS = 100
        # Newest first by the date of the commit each tag points at, a field the filtering and sorting syntax reaches.
        TAGS_NEWEST_FIRST = "-target.date".freeze

        def self.included(pack)
          repo = pack::REPO_PARAM
          pack.tool :redeploy,
                    summary: "Deploys an earlier deployment's commit again by running the pipeline that made it.",
                    description: "Roll back to an earlier deployment by starting again the pipeline that made it, on that deployment's " \
                                 "commit and with the same definition, every step from the start. A deployment step a person starts by " \
                                 "hand still waits for them in Bitbucket",
                    params_schema: CodeHost::Code.object_schema({
                      "repo" => repo, "deployment" => { "type" => "string", "description" => "The deployment's uuid, as recent_deployments shows it" }
                    }, %w[repo deployment]),
                    read_only: false

          pack.tool :list_tags,
                    summary: "Lists a repository's tags and the commit each one points at.",
                    description: "A repository's tags, newest commit first, with the commit each one points at, when it was made and its " \
                                 "message, narrowed to names holding some text when asked",
                    params_schema: CodeHost::Code.object_schema({
                      "repo" => repo,
                      "name" => { "type" => "string", "description" => "Only tags whose name holds this, such as v2 (optional)" },
                      "limit" => { "type" => "integer", "description" => "At most this many (optional, #{TAG_LIMIT}, at most #{MAX_TAGS})" }
                    }, %w[repo]),
                    read_only: true
        end

        def redeploy(environment_row:, arguments:)
          repo = repo_argument(arguments)
          bitbucket = api(environment_row)
          deployment = bitbucket.get("#{BitbucketApi.repository(repo)}/deployments/#{uuid_argument(arguments, 'deployment')}")
          commit = deployment.dig("release", "commit", "hash").to_s
          number = deployment.dig("release", "url").to_s[RESULTS_NUMBER, 1]
          named = "deployment #{deployment['uuid']} of #{commit[0, 12].presence || 'an unknown commit'}"
          fail_policy! "The #{named} names no pipeline that made it, so there is no pipeline to run again." if commit.empty? || number.nil?

          pipeline = Array(bitbucket.get("#{BitbucketApi.repository(repo)}/pipelines", "target.commit.hash" => commit, "pagelen" => Pipelines::PIPELINE_CANDIDATES)["values"])
                     .find { |each| each["build_number"].to_s == number }
          fail_policy! "Pipeline #{number}, which made the #{named}, is no longer among the pipelines on that commit, so it cannot be run again." unless pipeline

          started = start_again(bitbucket, repo, pipeline, "Pipeline #{number} in #{repo}")
          Telemetry.result("Deploying the #{named} again as pipeline #{started['build_number']} (#{started['uuid']}), running pipeline #{number} again on " \
                           "#{pipeline.dig('target', 'ref_name') || 'its commit'} at #{commit[0, 12]}, every step from the start. A deployment step a person " \
                           "starts by hand waits for them in Bitbucket. #{Pipelines::FOLLOW}.", link: pipeline_link(repo, started) || pipeline_link(repo, pipeline))
        end

        def list_tags(environment_row:, arguments:)
          repo = repo_argument(arguments)
          name = arguments["name"].to_s.strip
          fail! "name may hold only letters, digits and . _ - /" if name.present? && !name.match?(%r{\A[\w.\-/]+\z})

          query = { "sort" => TAGS_NEWEST_FIRST, "pagelen" => whole_number_argument(arguments, "limit", TAG_LIMIT, MAX_TAGS), "q" => (%(name ~ "#{name}") if name.present?) }.compact
          tags = Array(api(environment_row).get("#{BitbucketApi.repository(repo)}/refs/tags", query)["values"])
          text = if tags.empty?
            "#{repo} has no tags#{" holding #{name}" if name.present?}."
          else
            "Tags in #{repo}, newest commit first:\n#{tags.map { |tag| tag_line(tag) }.join("\n")}"
          end
          Telemetry.result(text, link: link([ @site, repo ].join("/")))
        end

        private

        def tag_line(tag)
          message = tag["message"].to_s.lines.first.to_s.strip.presence
          "  #{tag['name']}  #{tag.dig('target', 'hash').to_s[0, 12]}  #{tag['date'] || tag.dig('target', 'date')}#{"  #{message}" if message}"
        end

        # A deployment as a run, named for where it went, so a watch follows it and learns how long one takes.
        def deployment_run(deployment)
          deploy = deploy_of(deployment)
          state = deployment["state"] || {}
          Capabilities::History::Run.new(
            id: "#{DEPLOYMENT_RUN}#{deployment['uuid']}", name: "deployment to #{deployment['environment_name'].presence || 'an unnamed environment'}",
            status: deploy.status, started_at: deploy.started_at, finished_at: deploy.finished_at, url: deployment.dig("release", "url"),
            detail: "#{deployment.dig('release', 'name') || deploy.short} by #{state.dig('deployer', 'display_name') || 'unknown'}"
          )
        end

        def deployment_runs(bitbucket, repo) = deployments_of(bitbucket, repo).map { |deployment| deployment_run(deployment) }

        def one_deployment(bitbucket, repo, given)
          wanted = given.to_s.strip
          fail! "run must be a deployment's id as ci_runs gives it, such as #{DEPLOYMENT_RUN}<uuid>" if wanted.delete("{}").empty?

          found = deployments_of(bitbucket, repo).find { |deployment| deployment["uuid"].to_s.delete("{}").casecmp?(wanted.delete("{}")) }
          fail! "No deployment #{given} in #{repo}. ci_runs with an environment's name lists them." unless found

          Capabilities::History.result([ deployment_run(found) ], what: "deployments in #{repo}")
        end
      end
    end
  end
end

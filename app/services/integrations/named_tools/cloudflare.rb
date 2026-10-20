module Integrations
  module NamedTools
    # Changes Halon makes on Cloudflare often enough to have a tool of their own, each one request Firefight writes and runs
    # on the server's execute tool, every value a JSON literal, so each is granted, approved and stopped by its own name
    # rather than as a script. The requests are the ones Cloudflare's API reference gives: retry a Pages deployment
    # (POST .../pages/projects/{project_name}/deployments/{deployment_id}/retry), cancel a Workers build (PUT
    # .../builds/builds/{build_uuid}/cancel, Workers Builds API reference) and a deployment of a Worker that splits its
    # traffic between two versions (POST .../workers/scripts/{script_name}/deployments, strategy percentage), which a
    # deployment holds at most two of (Workers, Versions and deployments).
    module Cloudflare
      EXECUTE = ReadGuards::Cloudflare::TOOL
      RETRY = "retry_pages_deployment".freeze
      CANCEL = "cancel_workers_build".freeze
      SPLIT = "split_worker_traffic".freeze

      ACCOUNT_ID = /\A\h{32}\z/
      # A Pages project's name and a Worker's, as the API reference's patterns give them.
      PROJECT = /\A[a-z0-9][a-z0-9-]*\z/
      WORKER = /\A[a-z0-9_][a-z0-9_-]*\z/
      ID = /\A\h[\h-]*\z/
      # Cloudflare takes a share from 0.01 to 100 percent, and the shares add up to 100.
      SMALLEST_SHARE = 0.01

      ACCOUNT = { "type" => "string", "description" => "The Cloudflare account id, as the resource map names it" }.freeze

      DEFINITIONS = [
        ToolDefinition.new(
          name: RETRY, read_only: false, summary: "Runs a failed Cloudflare Pages deployment again.",
          description: "Run a Pages deployment again, such as one that failed for a timeout or a dependency that could not be " \
                       "fetched rather than its code. Cloudflare makes a new deployment from it, which run_history then follows",
          params_schema: { "type" => "object", "required" => %w[account_id project deployment], "properties" => {
            "account_id" => ACCOUNT, "project" => { "type" => "string", "description" => "The Pages project's name" },
            "deployment" => { "type" => "string", "description" => "The deployment to run again, by the id run_history or recent_deploys shows" }
          } }
        ),
        ToolDefinition.new(
          name: CANCEL, read_only: false, summary: "Cancels a queued or running Cloudflare Workers build.",
          description: "Cancel a Workers build that is queued or running, so what it builds is not deployed. A build already " \
                       "finished is not changed",
          params_schema: { "type" => "object", "required" => %w[account_id build], "properties" => {
            "account_id" => ACCOUNT, "build" => { "type" => "string", "description" => "The build, by the id run_history shows for the Worker" }
          } }
        ),
        ToolDefinition.new(
          name: SPLIT, read_only: false, summary: "Splits a Cloudflare Worker's traffic between two of its versions.",
          description: "Deploy a Worker with its traffic split between two of its versions by percentage, to send a share to a " \
                       "new version or to step back from a bad one gradually. The split holds until another deployment " \
                       "changes it. rollback sends all traffic to one version",
          params_schema: { "type" => "object", "required" => %w[account_id worker versions], "properties" => {
            "account_id" => ACCOUNT, "worker" => { "type" => "string", "description" => "The Worker's name" },
            "versions" => { "type" => "array", "minItems" => 2, "maxItems" => 2,
                            "description" => "The two versions, by the ids recent_deploys shows, each with its share. The shares add up to 100",
                            "items" => { "type" => "object", "required" => %w[version_id percentage], "properties" => {
                              "version_id" => { "type" => "string" }, "percentage" => { "type" => "number" }
                            } } },
            "message" => { "type" => "string", "description" => "Why, kept on the deployment (optional)" }
          } }
        )
      ].freeze

      def self.definitions = DEFINITIONS

      def self.handles?(tool_name) = DEFINITIONS.any? { |definition| definition.name == tool_name }

      # The server's tool and the arguments it takes for one call, refused in words before anything is sent when a value
      # could not be put in a path as given.
      def self.call_for(tool_name, arguments)
        given = arguments.to_h.stringify_keys
        account = matching(given, "account_id", ACCOUNT_ID, "a Cloudflare account id, 32 hexadecimal characters")
        options = case tool_name
        when RETRY
          project = matching(given, "project", PROJECT, "a Pages project's name")
          deployment = matching(given, "deployment", ID, "a deployment id")
          { "method" => "POST", "path" => "/accounts/#{account}/pages/projects/#{project}/deployments/#{deployment}/retry" }
        when CANCEL
          { "method" => "PUT", "path" => "/accounts/#{account}/builds/builds/#{matching(given, 'build', ID, 'a build id')}/cancel" }
        when SPLIT
          worker = matching(given, "worker", WORKER, "a Worker's name")
          message = given["message"].to_s.strip.presence || "Traffic split by Firefight"
          { "method" => "POST", "path" => "/accounts/#{account}/workers/scripts/#{worker}/deployments",
            "body" => { "strategy" => "percentage", "versions" => shares(given["versions"]), "annotations" => { "workers/message" => message.truncate(1000) } } }
        else raise Error, "Cloudflare has no tool #{tool_name} of Firefight's."
        end
        [ EXECUTE, script(options, account) ]
      end

      # What the call did, in words, with Cloudflare's own answer kept below them. An answer Cloudflare marked as failed
      # is the script's error and comes back as it was.
      def self.present(tool_name, arguments, result)
        return result if result["isError"]

        given = arguments.to_h.stringify_keys
        said = case tool_name
        when RETRY then "Pages deployment #{given['deployment']} of #{given['project']} is running again as a new deployment. run_history follows it."
        when CANCEL then "Workers build #{given['build']} is cancelled, so what it built is not deployed."
        when SPLIT
          "#{given['worker']} now serves #{Array(given['versions']).map { |version| "#{version['percentage']}% to version #{version['version_id']}" }.join(' and ')}."
        end
        content = Array(result["content"])
        result.merge("content" => [ { "type" => "text", "text" => said }, *content ])
      end

      def self.matching(given, name, pattern, what)
        value = given[name].to_s.strip
        raise Error, "#{name} must be #{what}." unless value.match?(pattern)

        value
      end

      def self.shares(versions)
        listed = Array(versions)
        raise Error, "versions must be two versions, each with its version_id and percentage." unless listed.size == 2 && listed.all?(Hash)

        split = listed.map do |version|
          id = version.stringify_keys["version_id"].to_s.strip
          share = Float(version.stringify_keys["percentage"], exception: false)
          raise Error, "version_id must be a version id, as recent_deploys shows it." unless id.match?(ID)
          raise Error, "percentage must be a number from #{SMALLEST_SHARE} to 100." unless share && share >= SMALLEST_SHARE && share <= 100

          { "version_id" => id, "percentage" => share }
        end
        raise Error, "The two versions must be different." if split.map { |version| version["version_id"] }.uniq.one?
        raise Error, "The percentages must add up to 100." unless (split.sum { |version| version["percentage"] } - 100).abs < 0.001

        split
      end

      # The one request, every value a JSON literal, with an answer Cloudflare marks as failed thrown, as the
      # capabilities' changes do (Capabilities::Cloudflare.script).
      def self.script(options, account)
        code = "async () => { const answer = await cloudflare.request(#{JSON.generate(options)}); " \
               "if (answer && (answer.success === false || (Array.isArray(answer.errors) && answer.errors.length > 0))) " \
               "throw new Error(JSON.stringify(answer.errors || answer)); return answer; }"
        { ReadGuards::Cloudflare::CODE => code, ReadGuards::Cloudflare::ACCOUNT => account }
      end

      private_class_method :matching, :shares, :script
    end
  end
end

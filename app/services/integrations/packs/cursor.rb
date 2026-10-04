module Integrations
  module Packs
    # Cursor's cloud agents, through the Cloud Agents API with a user's or a service account's key. A change is an agent
    # on the repository's address and branch with autoCreatePR, whose first run is followed by its status and the
    # branches and pull requests it pushed (Run.git.branches), and cancelled at the limit. Cursor's API has no spending
    # limit for an agent, so the time limit is the only one, and what it used is read from its usage in tokens.
    class Cursor < CodingAgent
      NAME = "Cursor".freeze
      # The longest name Cursor keeps for an agent.
      NAME_LIMIT = 100

      # Run.status, from Cursor's OpenAPI document.
      WORKING = %w[CREATING RUNNING].freeze
      STOPPED = { "ERROR" => "its run ended with an error", "CANCELLED" => "its run was cancelled", "EXPIRED" => "its run expired" }.freeze
      FINISHED = "FINISHED".freeze

      coding_tools!

      def self.credential_fields
        [
          CredentialField.new(key: API_KEY, label: "API key", secret: true, placeholder: "",
                              hint: "A user API key from the API Keys page of Cursor's dashboard, or a service account's key. Cloud agents reach the repository and open pull requests through the source control connected in Cursor.")
        ]
      end

      def self.credential_refusal(values, region: nil, fields: {})
        key = values[API_KEY].to_s.strip
        return "Paste a Cursor API key." if key.empty?

        CursorApi.new(key).me
        nil
      rescue CursorApi::Error => error
        "Cursor refused this key. #{error.message}"
      end

      def check_health!(environment_row)
        api(environment_row).me
      rescue CursorApi::Error => error
        fail! error.message
      end

      private

      def start(environment_row, repo:, base:, title:, prompt:)
        url = repository_url(repo) ||
              fail!("Cursor needs the repository's address, and #{repo} is not on the resource map. Give repo as the address its code host shows.")
        answer = api(environment_row).create_agent(
          "prompt" => { "text" => prompt }, "name" => title.truncate(NAME_LIMIT), "autoCreatePR" => true,
          "repos" => [ { "url" => url, "startingRef" => base }.compact ]
        )
        agent = answer["agent"] || {}
        id = agent["id"].presence || fail!("Cursor answered without an agent id.")
        run = answer.dig("run", "id").presence || agent["latestRunId"].presence || fail!("Cursor answered without a run.")
        Session.new(id: id, page: agent["url"].presence, handle: run)
      end

      def poll(environment_row, session)
        run = api(environment_row).run(session.id, session.handle)
        status = run["status"].to_s
        pull_requests = Array(run.dig("git", "branches")).filter_map { |branch| branch["prUrl"].presence if branch.is_a?(Hash) }
        phase = if status == FINISHED then PHASE_FINISHED
        elsif WORKING.include?(status) then PHASE_WORKING
        else PHASE_STOPPED
        end
        reason = STOPPED.fetch(status, "Cursor reported #{status.presence || 'nothing'}") if phase == PHASE_STOPPED
        State.new(phase: phase, reason: reason, pull_requests: pull_requests, words: run["result"].presence)
      end

      def stop(environment_row, session)
        api(environment_row).cancel(session.id, session.handle)
      end

      def session_for(environment_row, id)
        agent = api(environment_row).agent(id)
        Session.new(id: agent["id"].presence || id, page: agent["url"].presence,
                    handle: agent["latestRunId"].presence || fail!("Cursor has no run for the agent #{id}."))
      end

      # What the agent used, which is its only cost Cursor reports. A usage Cursor cannot give leaves the rest standing.
      def finished(environment_row, session, state)
        tokens = api(environment_row).usage(session.id).dig("totalUsage", "totalTokens")
        tokens ? state.with(spent: "#{tokens.to_i.to_fs(:delimited)} tokens") : state
      rescue CursorApi::Error
        state
      end

      def refused_hint(error)
        "Check the API key, or reconnect Cursor with a new one." if error.is_a?(CursorApi::Unauthorized)
      end

      def api(environment_row) = CursorApi.new(key_of(environment_row))
    end
  end
end

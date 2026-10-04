module Integrations
  module Packs
    # Factory's Droids, through Factory's public API with a Factory API key, on one Droid Computer per environment. A
    # change is a session on the computer, in the directory where the repository is cloned (the computer's
    # clonedRepoDirectories), sent the brief as its first message, with the autonomy Factory's docs give for work that
    # commits and pushes (high). A session is followed by its status until it is idle again, and interrupted at the
    # limit. A connection is in Factory's Global or EU deployment, chosen on the connect form. Factory returns no pull
    # request of its own and documents no page for a session, so the pull request is read from the Droid's own words and
    # is the only link. Factory reports what a session used in credits and has no limit for one, so the time limit is
    # the only one.
    class Factory < CodingAgent
      NAME = "Factory".freeze
      COMPUTER = "computer".freeze
      # Factory's interaction mode and autonomy for a Droid that edits, commits, pushes and opens a pull request.
      SESSION_SETTINGS = { "interactionMode" => "auto", "autonomyLevel" => "high" }.freeze
      # Session and computer statuses, from Factory's OpenAPI document.
      IDLE = "idle".freeze
      WORKING = %w[pending running].freeze
      COMPUTER_ACTIVE = "active".freeze
      COMPUTER_PROVISIONING = "provisioning".freeze
      # The most pages of the Droid's messages read for its last words and the pull requests it named.
      MESSAGE_PAGES = 10

      coding_tools!

      def self.credential_fields
        [
          CredentialField.new(key: API_KEY, label: "API key", secret: true, placeholder: "Your Factory API key",
                              hint: "A Factory API key, from Settings, API Keys in Factory. A service account's key keeps the work off a teammate's account. Factory switches its sessions API on for selected organizations."),
          CredentialField.new(key: COMPUTER, label: "Droid Computer", secret: false, placeholder: "my-computer",
                              hint: "The name of the Droid Computer the Droid works on, with your repositories cloned on it. A managed computer pushes and opens pull requests through the GitHub integration set up in Factory.")
        ]
      end

      # Reads the computer, so a wrong key, or a computer that is missing or not ready, is said on the form.
      def self.credential_refusal(values, region: nil, fields: {})
        key = values[API_KEY].to_s.strip
        name = values[COMPUTER].to_s.strip
        return "Paste a Factory API key." if key.empty?
        return "Enter the Droid Computer's name." if name.empty?

        computer_refusal(FactoryApi.new(key, region&.key).computer_named(name), name)
      rescue FactoryApi::Error => error
        "Factory refused this key or computer. #{error.message}"
      end

      def self.computer_refusal(computer, name)
        case computer["status"]
        when COMPUTER_PROVISIONING then "The Droid Computer #{name} is still being set up. Connect it once Factory shows it as active."
        when COMPUTER_ACTIVE, nil then nil
        else "Factory says the Droid Computer #{name} failed. Look at it under Settings, Droid Computers in Factory."
        end
      end

      def check_health!(environment_row)
        refusal = self.class.computer_refusal(computer(environment_row), computer_name(environment_row))
        fail! refusal if refusal
      rescue FactoryApi::Error => error
        fail! error.message
      end

      private

      def start(environment_row, repo:, prompt:, **)
        computer = computer(environment_row)
        created = api(environment_row).create_session("computerId" => computer["id"], "cwd" => directory_for(computer, repo),
                                                      "sessionSettings" => SESSION_SETTINGS)
        id = created["sessionId"].presence || fail!("Factory answered without a session id.")
        api(environment_row).send_message(id, prompt)
        Session.new(id: id)
      end

      # Once the Droid is idle again it has said its piece, which is where any pull request it opened is named.
      def poll(environment_row, session)
        answer = api(environment_row).session(session.id)
        status = answer["status"].to_s
        spent = answer["factoryCredits"] && "#{answer['factoryCredits'].to_f.round(2)} Factory credits"
        return State.new(phase: PHASE_WORKING, spent: spent) if WORKING.include?(status)
        return State.new(phase: PHASE_STOPPED, reason: "Factory reported #{status.presence || 'nothing'}", spent: spent) unless status == IDLE

        words = said_by_droid(environment_row, session)
        State.new(phase: PHASE_FINISHED, pull_requests: pull_requests_in(words.join("\n")), words: words.last, spent: spent)
      end

      def stop(environment_row, session)
        api(environment_row).interrupt(session.id)
      end

      def session_for(environment_row, id)
        api(environment_row).session(id)
        Session.new(id: id)
      end

      # The text of each of the Droid's messages, oldest first.
      def said_by_droid(environment_row, session)
        messages = []
        cursor = nil
        MESSAGE_PAGES.times do
          page = api(environment_row).messages(session.id, cursor: cursor)
          messages.concat(Array(page["messages"]).select { |message| message.is_a?(Hash) })
          cursor = page.dig("pagination", "nextCursor")
          break unless page.dig("pagination", "hasMore") && cursor.present?
        end
        messages.sort_by { |message| message["createdAt"].to_i }.filter_map do |message|
          Array(message["content"]).filter_map { |part| part["text"] if part.is_a?(Hash) && part["type"] == "text" }.join("\n").presence
        end
      end

      # The cloned directory whose last part is the repository's name, and with several, the one under its owner too.
      def directory_for(computer, repo)
        owner, name = repo.sub(%r{\Ahttps://[^/]+/}, "").delete_suffix(".git").split("/").last(2)
        named = Array(computer["clonedRepoDirectories"]).select { |path| File.basename(path.to_s) == name }
        named = named.select { |path| File.basename(File.dirname(path.to_s)) == owner } if named.size > 1
        return named.first if named.one?

        fail! "The Droid Computer #{computer['name'] || 'connected'} has #{named.empty? ? 'no copy' : 'several copies'} of #{repo}. " \
              "Clone it there once, then hand the change over again."
      end

      def refused_hint(error)
        case error.status
        when 401 then "Check the API key, or reconnect Factory with a new one."
        when 403 then "Factory switches its sessions API on for selected organizations, so ask Factory to switch it on for yours."
        end
      end

      def computer(environment_row) = api(environment_row).computer_named(computer_name(environment_row))

      def computer_name(environment_row)
        environment_row.credentials_hash[COMPUTER].presence || fail!("This environment has no Droid Computer. Reconnect it.")
      end

      # The connection's region picks Factory's Global or EU deployment.
      def api(environment_row) = FactoryApi.new(key_of(environment_row), ConnectionSettings.of(environment_row).region&.key)
    end
  end
end

module Integrations
  # Reads OpenCode 1.18.34, the version sandbox/Dockerfile pins, run with --format json. Each line is one event from
  # emit in packages/opencode/src/cli/cmd/run.ts. tool_use comes once a call completed or failed, with part.tool,
  # part.state.status, input, title and metadata, such as a command's exit code (tool/shell.ts) or a patch's files
  # (tool/apply_patch.ts). text comes once a piece of prose is finished, and error carries error.data.message. Only
  # paths, patterns and commands are read, never a file's content or a tool's output.
  class SandboxAgentEvents
    # The agent works in runner's copy, which sandbox/server.rb keeps under /runs.
    COPY = %r{\A/runs/[^/]+/?}
    # A command that runs a repository's tests, by how such commands start.
    TEST_RUNNER = %r{
      \A(?:[A-Z_][A-Z0-9_]*=\S*\s+)*
      (?:(?:bundle\s+exec|npx|pnpm\s+exec|yarn\s+exec|uv\s+run|poetry\s+run|python3?\s+-m|\.venv/bin/|bin/|\./)\s*)?
      (?:rails\s+test|rake\s+test|rspec|pytest|unittest|jest|vitest|mocha|go\s+test|cargo\s+test|mix\s+test|bun\s+test|deno\s+test|
         phpunit|make\s+test|(?:npm|yarn|pnpm)\s+(?:run\s+)?test|ruby\s+(?:-I\S*\s+)*\S*_test\.rb|test\b)
    }x
    # A value set on the command line under a name that says it is secret.
    SECRET_ASSIGNMENT = /\b([A-Za-z0-9_]*(?:TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|APIKEY|ACCESS_KEY|PRIVATE_KEY)[A-Za-z0-9_]*)=\S+/i
    THOUGHT_LIMIT = 140

    # hidden is what must never show, such as the agent's own token, should the agent ever print it.
    def initialize(progress, hidden: [])
      @progress = progress
      @hidden = hidden.compact_blank
    end

    # The agent's last words whole, which end with its summary of the change, for the review to read.
    attr_reader :progress, :last_said

    # A line that is not an event, such as the tail of one too long to hand over, is passed over.
    def read(text)
      text.to_s.each_line do |line|
        event = JSON.parse(line)
        @progress.live!
        take(event) if event.is_a?(Hash)
      rescue JSON::ParserError
        next
      end
      @progress
    end

    private

    def take(event)
      case event["type"]
      when "tool_use" then tool(event["part"].to_h)
      when "text" then thought(event.dig("part", "text"))
      when "error" then stopped(event["error"])
      end
    end

    def tool(part)
      state = part["state"].to_h
      input = state["input"].to_h
      failed = state["status"] == "error"
      case part["tool"].to_s
      when "read" then said("Read #{path(state['title'].presence || input['filePath'])}", failed)
      when "grep" then said([ "Searched for '#{input['pattern']}'", within(input) ].compact.join(" "), failed)
      when "glob" then said("Looked for files matching '#{input['pattern']}'", failed)
      when "list" then said("Listed #{path(input['path']).presence || 'the repository'}", failed)
      when "edit" then edited("Edited", state["title"].presence || input["filePath"], failed)
      when "write" then edited(state.dig("metadata", "exists") == false ? "Created" : "Wrote", state["title"].presence || input["filePath"], failed)
      when "apply_patch" then patched(state, failed)
      when "bash" then ran(input["command"], state, failed)
      when "lsp" then said("Asked the language server about #{path(input['filePath'])}", failed)
      when "todowrite" then said("Updated its plan", failed)
      when "task" then said("Handed '#{input['description']}' to a helper", failed)
      when "skill" then said("Loaded the #{input['name']} skill", failed)
      when "webfetch", /read_web_page\z/ then said("Read #{input['url']}", failed)
      when "websearch", /search_web\z/ then said("Searched the web for '#{input['query']}'", failed)
      when /#{CodeAgent::ReadTools::CALL}\z/o then said("Read with #{input['name']}", failed)
      when /#{CodeAgent::ReadTools::LIST}\z/o then said("Listed the tools it can read with", failed)
      when /#{CodeAgent::ReadTools::DESCRIBE}\z/o then said("Read how #{input['name']} works", failed)
      when /#{CodeAgent::ReadTools::SKILLS}\z/o then said("Listed the skills and guides", failed)
      when /#{CodeAgent::ReadTools::SKILL}\z/o then said(input["reference"].present? ? "Read #{input['reference']} from #{input['skill']}" : "Read the #{input['skill']} skill", failed)
      when /#{CodeAgent::QuestionTools::ASK}\z/o then said("Asked a question", failed)
      when /#{CodeAgent::QuestionTools::WAIT}\z/o then said("Waited for an answer", failed)
      when "invalid" then said("Tried a tool it does not have", true)
      else said("Used #{part['tool']}", failed)
      end
    end

    def said(text, failed) = @progress.add(hide(text), result: (Chat::CodeFixProgress::RESULT_FAILED if failed))

    def hide(text) = @hidden.reduce(text.to_s) { |shown, secret| shown.gsub(secret, "[REDACTED]") }

    def within(input)
      where = path(input["path"])
      kinds = input["include"].presence
      [ ("in #{where}" if where.present?), ("in #{kinds} files" if kinds) ].compact.join(" ").presence
    end

    # A failed edit changed nothing, so the file is only counted once one went through.
    def edited(verb, file, failed)
      relative = path(file)
      said("#{verb} #{relative}", failed)
      @progress.changed!(hide(relative)) unless failed
    end

    def patched(state, failed)
      touched = Array(state.dig("metadata", "files")).filter_map { |file| path(file["relativePath"].presence || file["filePath"]).presence }
      said(touched.one? ? "Edited #{touched.first}" : "Edited #{touched.size} files", failed)
      touched.each { |file| @progress.changed!(hide(file)) } unless failed
    end

    # A command that runs tests says whether they passed, and any other says only when it failed.
    def ran(command, state, failed)
      shown = command_line(command)
      exit_code = state.dig("metadata", "exit")
      broke = failed || (!exit_code.nil? && exit_code != 0)
      if test_command?(command)
        @progress.add(hide("Ran #{shown}"), result: broke ? Chat::CodeFixProgress::RESULT_FAILED : Chat::CodeFixProgress::RESULT_PASSED)
        @progress.tested!(hide(shown), passed: !broke)
      else
        said("Ran #{shown}", broke)
      end
    end

    def test_command?(command)
      command.to_s.split(/&&|\|\||;|\|/).map(&:strip).any? { |part| part.match?(TEST_RUNNER) }
    end

    def command_line(command) = command.to_s.lines.first.to_s.gsub(SECRET_ASSIGNMENT, '\1=[REDACTED]').strip

    # Prose the model writes between steps reads as its thinking, cut to its first sentence. Code it quotes is left out.
    def thought(text)
      @last_said = hide(text.to_s.strip) if text.present?
      words = text.to_s.split("```").first.to_s.squish
      return if words.blank?

      first = words[/\A.+?[.!?](?=\s|\z)/] || words
      @progress.add(hide("Thinking: #{first.truncate(THOUGHT_LIMIT)}"))
    end

    def stopped(error)
      error = error.to_h
      message = error.dig("data", "message").presence || error["name"].presence || "an error"
      @progress.add(hide("Stopped: #{unwrapped(message)}"), result: Chat::CodeFixProgress::RESULT_FAILED)
    end

    # A provider's refusal arrives as its own JSON body.
    def unwrapped(message)
      parsed = JSON.parse(message)
      parsed.is_a?(Hash) && parsed["message"].is_a?(String) ? parsed["message"] : message
    rescue JSON::ParserError
      message
    end

    def path(value) = value.to_s.sub(COPY, "")
  end
end

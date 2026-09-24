module Integrations
  module Packs
    class Github
      # Tools that read a repository in the run's sandbox, where every commit and the whole history are local. A
      # command reaches the box as an argument list, never a string, except in run_shell and run_tests, which only run
      # as unprivileged users in a box that holds no credential.
      module Code
        SEARCH_LINE_LIMIT = 300
        LOG_LIMIT = 30
        MAX_LOG_LIMIT = 200
        SHELL_TIMEOUT = 60
        MAX_SHELL_TIMEOUT = 120
        TESTS_TIMEOUT = 600
        MAX_TESTS_TIMEOUT = 20 * 60
        # Past this many repositories a definition search names the ones to look in rather than pushing them all.
        DEFINITION_REPO_LIMIT = 10
        LSP_QUESTIONS = {
          "definition" => "textDocument/definition", "references" => "textDocument/references",
          "hover" => "textDocument/hover", "symbols" => "workspace/symbol"
        }.freeze
        SERVICES = %w[postgres redis].freeze
        NOT_FOUND_ADVICE = "Frameworks also make methods nobody writes down, such as Rails route helpers ending in _path or " \
                           "_url, attribute readers and methods from define_method or method_missing. Search for how it " \
                           "could be generated before calling it missing.".freeze

        REPO = { "type" => "string", "description" => "Repository in owner/name form, e.g. acme/checkout" }.freeze
        REF = { "type" => "string", "description" => "Commit SHA, branch or tag, usually the running commit (optional, the default branch otherwise)" }.freeze

        def self.included(pack)
          pack.tool :list_files,
                    description: "List the files in a repository at a commit, optionally under one directory",
                    params_schema: object_schema({ "repo" => REPO, "ref" => REF, "path_prefix" => { "type" => "string", "description" => "Only paths under this directory (optional)" } }, %w[repo]),
                    read_only: true

          pack.tool :code_search,
                    description: "Regex search across a repository at a commit, returning path:line references with the matching line",
                    params_schema: object_schema({
                      "repo" => REPO, "ref" => REF,
                      "pattern" => { "type" => "string", "description" => "Extended regex to search for, e.g. def assign_clinician|AssignmentService" },
                      "path_prefix" => { "type" => "string", "description" => "Limit the search to paths under this prefix (optional)" }
                    }, %w[repo pattern]),
                    read_only: true

          pack.tool :find_definition,
                    description: "Where a class, module, method or function is defined, across one or several repositories at a commit. " \
                                 "Says so when nothing defines it, which is how a call to something missing is found",
                    params_schema: object_schema({
                      "symbol" => { "type" => "string", "description" => "The exact name, e.g. require_admin! or AssignmentService" },
                      "repos" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Repositories in owner/name form (optional, every repository this connection can see)" },
                      "ref" => REF
                    }, %w[symbol]),
                    read_only: true

          pack.tool :find_usages,
                    description: "Every place a name appears as a whole word in a repository at a commit",
                    params_schema: object_schema({
                      "repo" => REPO, "ref" => REF, "symbol" => { "type" => "string", "description" => "The exact name to look for" },
                      "path_prefix" => { "type" => "string", "description" => "Only paths under this prefix (optional)" }
                    }, %w[repo symbol]),
                    read_only: true

          pack.tool :git_log,
                    description: "A repository's history, newest first: commits touching a path, or the commits that added or removed some text (git log -S), " \
                                 "or whose changes match a regex (git log -G), optionally by author or time",
                    params_schema: object_schema({
                      "repo" => REPO, "ref" => REF,
                      "path" => { "type" => "string", "description" => "Only commits touching this path (optional)" },
                      "added_or_removed" => { "type" => "string", "description" => "Commits that changed how often this exact text appears, e.g. def require_admin! (optional)" },
                      "changed_lines_matching" => { "type" => "string", "description" => "Commits with an added or removed line matching this regex (optional)" },
                      "author" => { "type" => "string", "description" => "Only commits by this author (optional)" },
                      "since" => { "type" => "string", "description" => "Only commits after this time, e.g. 2026-09-01 (optional)" },
                      "until" => { "type" => "string", "description" => "Only commits before this time (optional)" },
                      "limit" => { "type" => "integer", "description" => "How many commits (optional, #{LOG_LIMIT}, at most #{MAX_LOG_LIMIT})" }
                    }, %w[repo]),
                    read_only: true

          pack.tool :show_commit,
                    description: "One commit in full: message, author, the files it changed and its diff, optionally only for one path",
                    params_schema: object_schema({
                      "repo" => REPO, "sha" => { "type" => "string", "description" => "The commit SHA" },
                      "path" => { "type" => "string", "description" => "Only the change to this path (optional)" }
                    }, %w[repo sha]),
                    read_only: true

          pack.tool :diff_refs,
                    description: "The diff between two commits, branches or tags in a repository, optionally only for one path",
                    params_schema: object_schema({
                      "repo" => REPO, "base" => { "type" => "string", "description" => "The earlier commit, branch or tag" },
                      "head" => { "type" => "string", "description" => "The later commit, branch or tag" },
                      "path" => { "type" => "string", "description" => "Only this path (optional)" }
                    }, %w[repo base head]),
                    read_only: true

          pack.tool :ask_language_server,
                    description: "Ask the language server for Ruby, TypeScript, JavaScript, Go or Python: the definition of what sits at a " \
                                 "line and column, every reference to it, its type and docs, or the symbols matching a name. More exact " \
                                 "than a text search when a name is common",
                    params_schema: object_schema({
                      "repo" => REPO, "ref" => REF,
                      "question" => { "type" => "string", "enum" => LSP_QUESTIONS.keys, "description" => "definition, references or hover need path, line and column. symbols needs query and language" },
                      "path" => { "type" => "string", "description" => "File the position is in" },
                      "line" => { "type" => "integer", "description" => "Line number, counting from 1" },
                      "column" => { "type" => "integer", "description" => "Column of the name, counting from 1" },
                      "query" => { "type" => "string", "description" => "Name to look for, for symbols" },
                      "language" => { "type" => "string", "enum" => %w[ruby typescript javascript go python], "description" => "For symbols, which language server to ask" }
                    }, %w[repo question]),
                    read_only: true

          pack.tool :run_shell,
                    description: "Run a read-only shell command in a checkout of a repository at a commit, for what the other tools do not cover. " \
                                 "It runs as a user that cannot write the code",
                    params_schema: object_schema({
                      "repo" => REPO, "ref" => REF, "command" => { "type" => "string", "description" => "The command, run with sh -c from the repository root" },
                      "timeout" => { "type" => "integer", "description" => "Seconds (optional, #{SHELL_TIMEOUT}, at most #{MAX_SHELL_TIMEOUT})" }
                    }, %w[repo command]),
                    read_only: true

          pack.tool :run_tests,
                    description: "Run a repository's own tests, or any command, in a writable copy at a commit. Its dependencies and tool " \
                                 "versions are installed first, once per copy. Postgres and Redis can be started for it",
                    params_schema: object_schema({
                      "repo" => REPO, "ref" => REF,
                      "command" => { "type" => "string", "description" => "The command, e.g. bin/rails test test/controllers/billing_controller_test.rb" },
                      "services" => { "type" => "array", "items" => { "type" => "string", "enum" => SERVICES }, "description" => "Services to start first, which set DATABASE_URL and REDIS_URL (optional)" },
                      "timeout" => { "type" => "integer", "description" => "Seconds (optional, #{TESTS_TIMEOUT}, at most #{MAX_TESTS_TIMEOUT})" }
                    }, %w[repo command]),
                    read_only: false
        end

        def self.object_schema(properties, required) = { "type" => "object", "properties" => properties, "required" => required }

        def list_files(environment_row:, arguments:)
          repo = repo_argument(arguments)
          result = code(environment_row).exec(repo, ref: ref_argument(arguments), where: Sandboxes::Client::IN_GIT,
                                                    argv: [ "ls-tree", "-r", "--name-only", Sandboxes::Client::COMMIT, "--", *optional_path(arguments, "path_prefix") ])
          files = result["stdout"].lines.map(&:chomp).reject { |path| path.match?(SENSITIVE_PATHS) }
          return "No files#{" under #{arguments['path_prefix']}" if arguments['path_prefix'].present?} in #{at(repo, result)}." if files.empty?

          "#{files.size} files in #{at(repo, result)}\n#{files.join("\n")}"
        end

        def code_search(environment_row:, arguments:)
          repo = repo_argument(arguments)
          pattern = required_text(arguments, "pattern")
          result = code(environment_row).exec(repo, ref: ref_argument(arguments), where: Sandboxes::Client::IN_GIT,
                                                    argv: [ "grep", "-n", "-I", "-E", "--full-name", "-e", pattern, Sandboxes::Client::COMMIT, "--", *optional_path(arguments, "path_prefix") ])
          hits(repo, result) || "No matches in #{at(repo, result)}."
        end

        def find_definition(environment_row:, arguments:)
          symbol = required_text(arguments, "symbol")
          repos = definition_repos(environment_row, arguments)
          reading = code(environment_row)
          found = repos.flat_map do |repo|
            result = reading.exec(repo, ref: ref_argument(arguments), where: Sandboxes::Client::IN_CHECKOUT, argv: [
              "sh", "-c", 'ctags -R -f - --fields=+nK --extras=-F . 2>/dev/null | awk -F "\t" -v wanted="$1" \'$1 == wanted\'', "find_definition", symbol
            ])
            definitions(repo, result)
          end
          return "#{symbol} is not defined in #{repos.join(', ')}. #{NOT_FOUND_ADVICE}" if found.empty?

          "#{symbol} is defined at\n#{found.join("\n")}"
        end

        def find_usages(environment_row:, arguments:)
          repo = repo_argument(arguments)
          symbol = required_text(arguments, "symbol")
          result = code(environment_row).exec(repo, ref: ref_argument(arguments), where: Sandboxes::Client::IN_GIT,
                                                    argv: [ "grep", "-n", "-I", "-w", "-F", "--full-name", "-e", symbol, Sandboxes::Client::COMMIT, "--", *optional_path(arguments, "path_prefix") ])
          hits(repo, result) || "#{symbol} does not appear in #{at(repo, result)}."
        end

        def git_log(environment_row:, arguments:)
          repo = repo_argument(arguments)
          limit = (Integer(arguments["limit"].to_s, exception: false) || LOG_LIMIT).clamp(1, MAX_LOG_LIMIT)
          filters = {
            "-S" => arguments["added_or_removed"], "-G" => arguments["changed_lines_matching"],
            "--author=" => arguments["author"], "--since=" => arguments["since"], "--until=" => arguments["until"]
          }.filter_map { |flag, value| value.present? && (flag.end_with?("=") ? "#{flag}#{value}" : [ flag, value.to_s ]) }.flatten
          result = code(environment_row).exec(repo, ref: ref_argument(arguments), where: Sandboxes::Client::IN_GIT, argv: [
            "log", "--format=%H%x09%aI%x09%an%x09%s", "-n", limit.to_s, *filters, Sandboxes::Client::COMMIT, "--", *optional_path(arguments, "path")
          ])
          commits = result["stdout"].lines.map { |line| line.chomp.split("\t", 4).then { |sha, at, author, subject| "#{sha[0, 12]}  #{at}  #{author}  #{subject}" } }
          return "No commits match in #{at(repo, result)}." if commits.empty?

          "#{commits.size} commits in #{at(repo, result)}, newest first\n#{commits.join("\n")}"
        end

        def show_commit(environment_row:, arguments:)
          repo = repo_argument(arguments)
          sha = ref_argument(arguments, "sha", required: true)
          result = code(environment_row).exec(repo, ref: sha, where: Sandboxes::Client::IN_GIT,
                                                    argv: [ "show", "--format=fuller", "--stat", "--patch", Sandboxes::Client::COMMIT, "--", *optional_path(arguments, "path") ])
          output(result)
        end

        def diff_refs(environment_row:, arguments:)
          repo = repo_argument(arguments)
          base = ref_argument(arguments, "base", required: true)
          head = ref_argument(arguments, "head", required: true)
          result = code(environment_row).exec(repo, ref: head, where: Sandboxes::Client::IN_GIT,
                                                    argv: [ "diff", "--stat", "--patch", base, Sandboxes::Client::COMMIT, "--", *optional_path(arguments, "path") ])
          result["stdout"].strip.empty? ? "No difference between #{base} and #{head} in #{repo}." : output(result)
        end

        def ask_language_server(environment_row:, arguments:)
          repo = repo_argument(arguments)
          question = arguments["question"].to_s
          method = LSP_QUESTIONS[question] || fail!("question must be one of #{LSP_QUESTIONS.keys.join(', ')}")
          request = if question == "symbols"
            { query: required_text(arguments, "query"), language: required_text(arguments, "language") }
          else
            { path: path_argument(arguments), line: whole_number(arguments, "line"), column: whole_number(arguments, "column") }
          end
          answer = code(environment_row).lsp(repo, method: method, ref: ref_argument(arguments), **request)
          language_answer(repo, question, answer)
        end

        def run_shell(environment_row:, arguments:)
          running_commands!
          repo = repo_argument(arguments)
          result = code(environment_row).exec(repo, ref: ref_argument(arguments), where: Sandboxes::Client::IN_CHECKOUT,
                                                    argv: [ "sh", "-c", required_text(arguments, "command") ],
                                                    timeout: seconds(arguments, SHELL_TIMEOUT, MAX_SHELL_TIMEOUT))
          "#{at(repo, result)}\n#{output(result)}"
        end

        def run_tests(environment_row:, arguments:)
          running_commands!
          repo = repo_argument(arguments)
          ref = ref_argument(arguments)
          services = Array(arguments["services"]).map(&:to_s)
          fail! "services can only be #{SERVICES.join(' and ')}" unless (services - SERVICES).empty?

          reading = code(environment_row)
          prepared = reading.prepare(repo, ref: ref)
          result = reading.exec(repo, ref: ref, where: Sandboxes::Client::IN_COPY, argv: [ "sh", "-c", required_text(arguments, "command") ],
                                      services: services.presence, timeout: seconds(arguments, TESTS_TIMEOUT, MAX_TESTS_TIMEOUT))
          [ at(repo, result), preparation(prepared), output(result) ].compact.join("\n\n")
        end

        private

        def code(environment_row) = CodeReading.new(key: box_key, workspace: integration.workspace, environment_row: environment_row)

        # Commands a repository chooses reach the network, so they wait for the workspace's AI SRE switch.
        def running_commands!
          return if FeatureFlags.enabled?(integration.workspace, FeatureFlags::AI_SRE)

          fail! "Running commands in the code sandbox is not switched on for this workspace."
        end

        def definition_repos(environment_row, arguments)
          named = Array(arguments["repos"]).map { |repo| repo_argument({ "repo" => repo.to_s }) }
          return named if named.any?

          visible = Array(GithubApp.get("/installation/repositories?per_page=100", token: GithubApp.installation_token(environment_row))["repositories"]).map { |repository| repository["full_name"] }
          fail! "This connection can see no repositories." if visible.empty?
          if visible.size > DEFINITION_REPO_LIMIT
            fail! "This connection can see #{visible.size} repositories. Name the ones to look in with repos, at most #{DEFINITION_REPO_LIMIT}."
          end

          visible
        end

        def definitions(repo, result)
          result["stdout"].lines.filter_map do |line|
            _name, path, _address, *fields = line.chomp.split("\t")
            next if path.blank? || path.delete_prefix("./").match?(SENSITIVE_PATHS)

            kind = fields.find { |field| field.start_with?("kind:") }&.delete_prefix("kind:")
            number = fields.find { |field| field.start_with?("line:") }&.delete_prefix("line:")
            "#{repo}  #{path.delete_prefix('./')}:#{number}  #{kind} (at #{result['commit'][0, 12]})"
          end
        end

        # git grep prints commit:path:line:text, and the commit is said once in the heading instead.
        def hits(repo, result)
          lines = result["stdout"].lines.filter_map do |line|
            location = line.chomp.delete_prefix("#{result['commit']}:")
            location.truncate(SEARCH_LINE_LIMIT) unless location.split(":", 2).first.to_s.match?(SENSITIVE_PATHS)
          end
          lines.any? && "#{lines.size} matches in #{at(repo, result)}\n#{lines.join("\n")}"
        end

        def language_answer(repo, question, answer)
          result = answer["result"]
          root = "file://#{answer['root']}/"
          heading = "#{repo} at #{answer['commit'][0, 12]}"
          return "The language server has no #{question} for that in #{heading}." if result.blank?
          return "#{heading}\n#{hover_text(result['contents'])}" if question == "hover"

          lines = Array.wrap(result).filter_map do |entry|
            location = entry["location"] || entry
            uri = location["uri"] || location["targetUri"]
            range = location["range"] || location["targetSelectionRange"] || location["targetRange"]
            next unless uri&.start_with?(root)

            where = "#{CGI.unescape(uri.delete_prefix(root))}:#{range.dig('start', 'line').to_i + 1}"
            entry["name"] ? "#{entry['name']}  #{where}" : where
          end
          "#{lines.size} results in #{heading}\n#{lines.join("\n")}"
        end

        def hover_text(contents)
          case contents
          when Hash then contents["value"].to_s
          when Array then contents.map { |part| part.is_a?(Hash) ? part["value"] : part }.join("\n")
          else contents.to_s
          end
        end

        def preparation(prepared)
          return nil if prepared["already"] || prepared["prepared"].empty?

          steps = prepared["prepared"].map do |step|
            "#{step['command']} (for #{step['file']}) exited #{step['exit_code']}#{"\n#{step['output']}" unless step['exit_code'].zero?}"
          end
          "Installed first:\n#{steps.join("\n")}"
        end

        def output(result)
          notes = []
          notes << "It was stopped after its time limit." if result["timed_out"]
          notes << "Its output was cut at 10 MB." if result["truncated"]
          [ ("exit #{result['exit_code']}" unless result["exit_code"].to_i.zero?), result["stdout"].presence,
            (result["stderr"].presence if result["exit_code"].to_i.nonzero?), *notes ].compact.join("\n")
        end

        def at(repo, result) = "#{repo} at #{result['commit'].to_s[0, 12]}"

        def optional_path(arguments, key)
          value = arguments[key].to_s
          return [] if value.blank?

          path_argument({ "path" => value })
          [ value ]
        end

        def required_text(arguments, key)
          value = arguments[key].to_s
          fail! "#{key} is required" if value.strip.empty?

          value
        end

        def whole_number(arguments, key)
          Integer(arguments[key].to_s, exception: false)&.then { |number| number if number.positive? } || fail!("#{key} must be a whole number from 1")
        end

        def seconds(arguments, default, most)
          (Integer(arguments["timeout"].to_s, exception: false) || default).clamp(1, most)
        end
      end
    end
  end
end

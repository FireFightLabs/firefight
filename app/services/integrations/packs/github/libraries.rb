module Integrations
  module Packs
    class Github
      # A library the repository depends on, at the version it installs, read in the run's sandbox after the repository's
      # own preparation. Where the library sits is asked of its own ecosystem, so a name is never guessed into a path.
      module Libraries
        LIBRARY_TIMEOUT = 120
        FILES_SHOWN = 200
        MATCHES_SHOWN = 60
        LINES_SHOWN = 400
        # Asks bundler, node, python and go in turn, and prints the first answer as its version and folder.
        FIND = <<~'SH'.freeze
          name="$1"
          found() { printf 'FOUND\t%s\t%s\n' "$1" "$2"; exit 0; }
          if [ -f Gemfile.lock ]; then
            dir=$(bundle info --path "$name" 2>/dev/null) && [ -d "$dir" ] && found "$(bundle info "$name" 2>/dev/null | sed -n 's/.*(\(.*\)).*/\1/p' | head -1)" "$dir"
          fi
          if [ -f "node_modules/$name/package.json" ]; then
            found "$(node -p "require('./node_modules/$name/package.json').version" 2>/dev/null)" "$PWD/node_modules/$name"
          fi
          if [ -x .venv/bin/python ]; then
            out=$(.venv/bin/python - "$name" <<'PY' 2>/dev/null
          import sys, importlib.metadata as m, os
          d = m.distribution(sys.argv[1])
          code = [str(f).split("/")[0] for f in (d.files or []) if str(f).endswith(".py") and ".dist-info" not in str(f) and not str(f).startswith("..")]
          if not code: sys.exit(1)
          print(d.version); print(os.path.join(str(d.locate_file("")), max(set(code), key=code.count)))
          PY
            ) && found "$(echo "$out" | sed -n 1p)" "$(echo "$out" | sed -n 2p)"
          fi
          if [ -f go.mod ]; then
            out=$(go list -m -f '{{.Version}} {{.Dir}}' "$name" 2>/dev/null) && [ -n "$out" ] && found "${out%% *}" "${out#* }"
          fi
          echo "MISSING"
        SH
        # Then one of three looks inside it, never outside.
        LOOK = <<~'SH'.freeze
          dir="$1"; how="$2"; what="$3"
          cd "$dir" || exit 3
          root=$(pwd -P)
          case "$how" in
            read)
              real=$(realpath -e -- "$what" 2>/dev/null) || { echo "MISSING"; exit 0; }
              case "$real" in "$root"/*) sed -n "1,${4}p" -- "$real" ;; *) echo "OUTSIDE" ;; esac ;;
            search) rg -n --no-heading --no-follow -m 5 -e "$what" . | head -n "$4" ;;
            *) find . -type f -not -path './.git/*' | sort | head -n "$4" ;;
          esac
        SH

        def self.included(pack)
          pack.tool :library_source,
                    description: "The source and bundled docs of a library this repository depends on, at the exact version it " \
                                 "installs: its version and files, a search in it, or one file. Read how a library really behaves " \
                                 "before relying on it",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO, "ref" => Code::REF,
                      "library" => { "type" => "string", "description" => "The library's name as the repository depends on it, such as sidekiq, @aws-sdk/client-s3, requests or github.com/redis/go-redis/v9" },
                      "pattern" => { "type" => "string", "description" => "A regular expression to search for in the library (optional)" },
                      "path" => { "type" => "string", "description" => "One file in the library to read, relative to its folder (optional)" }
                    }, %w[repo library]),
                    read_only: true
        end

        def library_source(environment_row:, arguments:)
          running_commands!
          repo = repo_argument(arguments)
          ref = ref_argument(arguments)
          library = required_text(arguments, "library")
          fail! "library must be a package name" unless library.match?(%r{\A[@\w][@\w.\-/]*\z}) && !library.include?("..")

          reading = code(environment_row)
          reading.prepare(repo, ref: ref)
          found = reading.exec(repo, ref: ref, where: Sandboxes::Client::IN_COPY, timeout: LIBRARY_TIMEOUT, argv: [ "bash", "-c", FIND, "find", library ])
          _, version, dir = found["stdout"].to_s.lines.find { |line| line.start_with?("FOUND\t") }.to_s.chomp.split("\t")
          return "#{library} is not installed in #{at(repo, found)}. Check the name the repository depends on it by." if dir.blank?

          how, what, limit = look(arguments)
          looked = reading.exec(repo, ref: ref, where: Sandboxes::Client::IN_COPY, timeout: LIBRARY_TIMEOUT, argv: [ "bash", "-c", LOOK, "look", dir, how, what.to_s, limit.to_s ])
          text = looked["stdout"].to_s
          fail! "path must be inside the library" if text.start_with?("OUTSIDE")
          return "#{arguments['path']} is not a file in #{library}." if text.start_with?("MISSING")

          "#{library} #{version.presence || 'at an unknown version'}, installed for #{at(repo, found)}\n#{text.presence || 'Nothing matched.'}"
        end

        private

        def look(arguments)
          return [ "read", arguments["path"].to_s, LINES_SHOWN ] if arguments["path"].present?
          return [ "search", arguments["pattern"].to_s, MATCHES_SHOWN ] if arguments["pattern"].present?

          [ "list", "", FILES_SHOWN ]
        end
      end
    end
  end
end

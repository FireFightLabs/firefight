module Integrations
  # The checks a code change gets in the sandbox before anyone reviews it, for the files the pull request changes only: a
  # workflow linter for CI workflows, the repository's own linters and type checker where it installed them, the tests it
  # changed and the tests that cover the files it changed, and a syntax check for configuration. A check whose tool the
  # repository or the box does not have is skipped, never installed, so a check never reaches the web. SCRIPT runs in the
  # copy after the agent, with the change staged, as a shell function the run calls with the commit the pull request's
  # change is measured from, where it leaves its base branch.
  module CodeChecks
    # Each check stops at this, so a slow suite cannot hold the change past its time.
    CHECK_TIMEOUT = 180
    OUTPUT_KEPT = 4_000

    # reason says what a check that could not run was missing, and is nil otherwise.
    Check = Data.define(:name, :status, :output, :reason) do
      def initialize(reason: nil, **) = super

      def passed? = status == PASSED

      def failed? = status == FAILED

      def could_not_run? = status == COULD_NOT_RUN
    end
    PASSED = "passed".freeze
    FAILED = "failed".freeze
    TIMED_OUT = "timed out".freeze
    # Stopped by something the box lacks, such as a database, so it says nothing about the change.
    COULD_NOT_RUN = "could not run".freeze

    # What a check that stopped this way was missing, read from what it printed. Checked in order, so a database refusing
    # a connection reads as a database rather than as any service.
    MISSING = [
      [ Regexp.union(/PG::ConnectionBad|ActiveRecord::(ConnectionNotEstablished|NoDatabaseError|DatabaseConnectionError)/,
                     /could not connect to (the )?server|connection to server (at|on) .* failed/,
                     /Can't connect to (local )?MySQL server|Mysql2::Error::ConnectionError|psycopg2?\.OperationalError|SQLSTATE\[HY000\] \[2002\]/),
        "no database was available" ],
      [ /Redis::CannotConnectError|Error connecting to Redis/i, "no Redis was available" ],
      [ /ActiveSupport::EncryptedFile::MissingKeyError|key not found: "[A-Z][A-Z0-9_]*"/, "secrets or settings it needs were not set" ],
      [ /ECONNREFUSED|Connection refused/, "a service it needs was not running" ]
    ].freeze
    # A shell's codes for a command it could not find or run.
    NOT_INSTALLED = [ 126, 127 ].freeze

    SCRIPT = <<~'SH'.gsub("CHECK_TIMEOUT", CHECK_TIMEOUT.to_s).gsub("OUTPUT_KEPT", OUTPUT_KEPT.to_s).freeze
      run_checks() {
        changed=$(git diff --cached --no-renames --diff-filter=d --name-only "$1")
        [ -z "$changed" ] && return 0
        check() {
          label=$1; shift
          out=$(timeout CHECK_TIMEOUT "$@" 2>&1 < /dev/null); code=$?
          printf 'CHECK\t%s\t%s\t%s\n' "$(printf '%s' "$label" | base64 -w0)" "$code" "$(printf '%s' "$out" | tail -c OUTPUT_KEPT | base64 -w0)"
        }
        pick() { printf '%s\n' "$changed" | grep -E "$1" | tr '\n' ' '; }
        has() { command -v "$1" > /dev/null 2>&1; }
        workflows=$(pick '^\.github/workflows/[^/]+\.ya?ml$')
        [ -n "$workflows" ] && has actionlint && check "actionlint $workflows" actionlint $workflows
        ruby=$(pick '\.rb$')
        if [ -n "$ruby" ] && [ -f Gemfile.lock ] && grep -q '^    rubocop ' Gemfile.lock; then check "rubocop $ruby" bundle exec rubocop --force-exclusion $ruby; fi
        # The tests beside a changed file by the repository's own layout, app/models/user.rb by test/models/user_test.rb.
        covering() {
          for file in $changed; do
            case "$file" in
              *_test.rb|*_spec.rb|*.test.*|*.spec.*|*/test_*.py|test_*.py) continue ;;
              *.rb)
                for candidate in "$(printf '%s' "$file" | sed -E 's#(^|/)app/#\1test/#; s#\.rb$#_test.rb#')" "test/${file%.rb}_test.rb" \
                                 "$(printf '%s' "$file" | sed -E 's#(^|/)app/#\1spec/#; s#\.rb$#_spec.rb#')" "spec/${file%.rb}_spec.rb"; do
                  [ -f "$candidate" ] && echo "$candidate"
                done ;;
              *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs)
                for kind in test spec; do [ -f "${file%.*}.$kind.${file##*.}" ] && echo "${file%.*}.$kind.${file##*.}"; done ;;
              *.py)
                for candidate in "$(dirname "$file")/test_$(basename "$file")" "tests/test_$(basename "$file")" "test/test_$(basename "$file")"; do
                  [ -f "$candidate" ] && echo "$candidate"
                done ;;
            esac
          done
          return 0
        }
        related=$(covering)
        # A test the change touched or one that covers a file it touched.
        tests_of() { printf '%s\n%s\n' "$changed" "$related" | grep -E "$1" | sort -u | tr '\n' ' '; }
        tests=$(tests_of '^test/.*_test\.rb$')
        if [ -n "$tests" ]; then if [ -x bin/rails ]; then check "bin/rails test $tests" bin/rails test $tests; else check "ruby test $tests" bundle exec ruby -Itest -e 'ARGV.each { |file| require "./#{file}" }' $tests; fi; fi
        specs=$(tests_of '^spec/.*_spec\.rb$')
        [ -n "$specs" ] && [ -f Gemfile.lock ] && grep -q '^    rspec-core ' Gemfile.lock && check "rspec $specs" bundle exec rspec $specs
        scripts=$(pick '\.(js|jsx|ts|tsx|mjs|cjs)$')
        [ -n "$scripts" ] && [ -x node_modules/.bin/eslint ] && check "eslint $scripts" node_modules/.bin/eslint $scripts
        typed=$(pick '\.(ts|tsx)$')
        [ -n "$typed" ] && [ -f tsconfig.json ] && [ -x node_modules/.bin/tsc ] && check "tsc --noEmit" node_modules/.bin/tsc --noEmit -p .
        jstests=$(tests_of '\.(test|spec)\.(js|jsx|ts|tsx|mjs|cjs)$')
        if [ -n "$jstests" ]; then
          if [ -x node_modules/.bin/vitest ]; then check "vitest run $jstests" node_modules/.bin/vitest run $jstests
          elif [ -x node_modules/.bin/jest ]; then check "jest $jstests" node_modules/.bin/jest $jstests; fi
        fi
        python=$(pick '\.py$')
        if [ -n "$python" ]; then
          if [ -x .venv/bin/ruff ]; then check "ruff check $python" .venv/bin/ruff check $python; elif has ruff; then check "ruff check $python" ruff check $python; fi
          check "python compile $python" python3 -m py_compile $python
        fi
        pytests=$(tests_of '(^|/)(test_[^/]*|[^/]*_test)\.py$')
        [ -n "$pytests" ] && [ -x .venv/bin/pytest ] && check "pytest $pytests" .venv/bin/pytest $pytests
        gofiles=$(pick '\.go$')
        if [ -n "$gofiles" ] && has go; then
          check "gofmt -l $gofiles" sh -c 'out=$(gofmt -l "$@"); [ -z "$out" ] || { echo "$out"; exit 1; }' gofmt $gofiles
          packages=$(for file in $gofiles; do echo "./$(dirname "$file")"; done | sort -u | tr '\n' ' ')
          check "go vet $packages" go vet $packages
          tested=$(for package in $packages; do ls "$package"/*_test.go > /dev/null 2>&1 && echo "$package"; done | tr '\n' ' ')
          [ -n "$tested" ] && check "go test $tested" go test $tested
        fi
        shells=$(pick '\.(sh|bash)$')
        [ -n "$shells" ] && has shellcheck && check "shellcheck $shells" shellcheck $shells
        for file in $(pick '\.json$'); do check "json $file" python3 -m json.tool "$file"; done
        for file in $(pick '\.ya?ml$'); do check "yaml $file" ruby -ryaml -e 'YAML.load_stream(File.read(ARGV[0]))' "$file"; done
        return 0
      }
    SH

    # The checks a run printed, from its CHECK lines.
    def self.read(lines)
      lines.filter_map do |line|
        kind, name, code, output = line.chomp.split("\t", 4)
        next unless kind == "CHECK"

        said = decoded(output)
        reason = missing(code.to_i, said)
        Check.new(name: decoded(name).squish.truncate(200), status: reason ? COULD_NOT_RUN : status(code.to_i), output: Chat::SecretFree.redacted(said),
                  reason: reason)
      end
    end

    def self.status(code)
      return PASSED if code.zero?

      code == 124 ? TIMED_OUT : FAILED
    end

    # Why a failed check could not run at all, or nil when it ran and failed.
    def self.missing(code, output)
      return if code.zero? || code == 124
      return "its command is not installed" if NOT_INSTALLED.include?(code)

      MISSING.find { |pattern, _reason| output.match?(pattern) }&.last
    end

    def self.decoded(text) = Base64.decode64(text.to_s).force_encoding(Encoding::UTF_8).scrub

    # How the checks went, as the review reads them. One that could not run says why and nothing more, since what it
    # printed is about the box rather than the change.
    def self.summary(checks)
      return "No check could run on the files this change touched, since the repository has none of the tools for them." if checks.empty?

      checks.map do |check|
        line = "- #{check.name}: #{check.status}"
        next line if check.passed?
        next "#{line} here, since #{check.reason}. This says nothing about the change." if check.could_not_run?

        "#{line}\n#{check.output.strip.lines.last(30).join.presence || '(it printed nothing)'}"
      end.join("\n")
    end
  end
end

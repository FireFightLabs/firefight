module Integrations
  # The checks a code change gets in the sandbox before anyone reviews it, for the files it changed only: a workflow
  # linter for CI workflows, the repository's own linters and type checker where it installed them, the tests it changed,
  # and a syntax check for configuration. A check whose tool the repository or the box does not have is skipped, never
  # installed, so a check never reaches the web. SCRIPT runs in the copy after the agent, with the change staged, as
  # a shell function the run calls with the commit the copy started at.
  module CodeChecks
    # Each check stops at this, so a slow suite cannot hold the change past its time.
    CHECK_TIMEOUT = 180
    OUTPUT_KEPT = 4_000

    Check = Data.define(:name, :status, :output) do
      def passed? = status == PASSED

      def failed? = status == FAILED
    end
    PASSED = "passed".freeze
    FAILED = "failed".freeze
    TIMED_OUT = "timed out".freeze

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
        tests=$(pick '^test/.*_test\.rb$')
        if [ -n "$tests" ]; then if [ -x bin/rails ]; then check "bin/rails test $tests" bin/rails test $tests; else check "ruby test $tests" bundle exec ruby -Itest -e 'ARGV.each { |file| require "./#{file}" }' $tests; fi; fi
        specs=$(pick '^spec/.*_spec\.rb$')
        [ -n "$specs" ] && [ -f Gemfile.lock ] && grep -q '^    rspec-core ' Gemfile.lock && check "rspec $specs" bundle exec rspec $specs
        scripts=$(pick '\.(js|jsx|ts|tsx|mjs|cjs)$')
        [ -n "$scripts" ] && [ -x node_modules/.bin/eslint ] && check "eslint $scripts" node_modules/.bin/eslint $scripts
        typed=$(pick '\.(ts|tsx)$')
        [ -n "$typed" ] && [ -f tsconfig.json ] && [ -x node_modules/.bin/tsc ] && check "tsc --noEmit" node_modules/.bin/tsc --noEmit -p .
        jstests=$(pick '\.(test|spec)\.(js|jsx|ts|tsx|mjs|cjs)$')
        if [ -n "$jstests" ]; then
          if [ -x node_modules/.bin/vitest ]; then check "vitest run $jstests" node_modules/.bin/vitest run $jstests
          elif [ -x node_modules/.bin/jest ]; then check "jest $jstests" node_modules/.bin/jest $jstests; fi
        fi
        python=$(pick '\.py$')
        if [ -n "$python" ]; then
          if [ -x .venv/bin/ruff ]; then check "ruff check $python" .venv/bin/ruff check $python; elif has ruff; then check "ruff check $python" ruff check $python; fi
          check "python compile $python" python3 -m py_compile $python
        fi
        pytests=$(pick '(^|/)(test_[^/]*|[^/]*_test)\.py$')
        [ -n "$pytests" ] && [ -x .venv/bin/pytest ] && check "pytest $pytests" .venv/bin/pytest $pytests
        gofiles=$(pick '\.go$')
        if [ -n "$gofiles" ] && has go; then
          check "gofmt -l $gofiles" sh -c 'out=$(gofmt -l "$@"); [ -z "$out" ] || { echo "$out"; exit 1; }' gofmt $gofiles
          packages=$(for file in $gofiles; do echo "./$(dirname "$file")"; done | sort -u | tr '\n' ' ')
          check "go vet $packages" go vet $packages
          gotests=$(pick '_test\.go$')
          [ -n "$gotests" ] && check "go test $packages" go test $packages
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

        Check.new(name: decoded(name).squish.truncate(200), status: status(code.to_i), output: Chat::SecretFree.redacted(decoded(output)))
      end
    end

    def self.status(code)
      return PASSED if code.zero?

      code == 124 ? TIMED_OUT : FAILED
    end

    def self.decoded(text) = Base64.decode64(text.to_s).force_encoding(Encoding::UTF_8).scrub

    # How the checks went, as the review and the pull request read them.
    def self.summary(checks)
      return "No check could run on the files this change touched, since the repository has none of the tools for them." if checks.empty?

      checks.map do |check|
        line = "- #{check.name}: #{check.status}"
        check.passed? ? line : "#{line}\n#{check.output.strip.lines.last(30).join.presence || '(it printed nothing)'}"
      end.join("\n")
    end
  end
end

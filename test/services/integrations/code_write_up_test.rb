require "test_helper"

module Integrations
  class CodeWriteUpTest < ActiveSupport::TestCase
    Fixing = Packs::Github::Fixing

    setup do
      @checks = [
        CodeChecks::Check.new(name: "actionlint .github/workflows/release.yml", status: CodeChecks::PASSED, output: ""),
        CodeChecks::Check.new(name: "bin/rails test test/models/pool_test.rb", status: CodeChecks::COULD_NOT_RUN, output: "PG::ConnectionBad",
                              reason: "no database was available")
      ]
      @change = Fixing::Change.new(commit: "c" * 40, log: "", agent_exit: 0, base: "b" * 40, checks: @checks, patch: "",
                                   counts: { ".github/workflows/release.yml" => [ 3, 1 ] }, touched: [ ".github/workflows/release.yml", "Archspec.rb" ], merged: true)
      @reviewed = Fixing::Reviewed.new(ran: true, right: true, findings: [], unverified: [ "Whether Northflank limits how long a run name may be." ], unreviewed: [],
                                       verified: [ "The run name holds only letters, digits and hyphens, which Northflank's error message says it allows." ],
                                       summary: "Sanitizes the run name.", sent_back: false)
    end

    test "the body leads with what the change does, then what was verified, what could not run here and the open questions, in plain copy" do
      body = CodeWriteUp.body(lead: "Replaces the dots in the release run name with hyphens, since Northflank refuses dots.", context: nil,
                              warning: CodeChange::CI_WARNING, reviewed: @reviewed, change: @change)

      assert_equal <<~TEXT.strip, body
        Replaces the dots in the release run name with hyphens, since Northflank refuses dots.

        #{CodeChange::CI_WARNING}

        **Verified**
        - `actionlint .github/workflows/release.yml` passed.
        - The run name holds only letters, digits and hyphens, which Northflank's error message says it allows.

        **Could not run here**
        - `bin/rails test test/models/pool_test.rb`: no database was available.

        **Open questions**
        - Whether Northflank limits how long a run name may be.

        **Files**
        - `.github/workflows/release.yml` (+3 -1)

        #{CodeWriteUp::FOOTER}
      TEXT
      assert_no_dashes_or_semicolons body
    end

    test "a check that could not run is never an open question or a failed check" do
      body = CodeWriteUp.body(lead: "Raises the pool.", context: nil, warning: nil, reviewed: @reviewed.with(unverified: []), change: @change)

      assert_not_includes body, "Open questions"
      assert_not_includes body, "did not pass"
      assert_includes body, "**Could not run here**\n- `bin/rails test test/models/pool_test.rb`: no database was available."
    end

    test "what the agent's summary says could not run here joins the checks that could not, each a sentence" do
      change = @change.with(not_run: [ "`bin/rails test test/system`, since no browser was installed", "The full suite needs Redis." ])
      body = CodeWriteUp.body(lead: "Raises the pool.", context: nil, warning: nil, reviewed: @reviewed, change: change)

      assert_includes body, "**Could not run here**\n- `bin/rails test test/models/pool_test.rb`: no database was available.\n" \
                            "- `bin/rails test test/system`, since no browser was installed.\n- The full suite needs Redis.\n\n**Open questions**"
      assert_includes CodeWriteUp.answer(done: "Opened it.", warning: nil, reviewed: @reviewed, change: change, base: "main", updating: false),
                      "- The full suite needs Redis."
    end

    test "a repository with no CI says so plainly in the body, the comment and the answer, after what could not run, and one with CI says nothing" do
      said = "acme/api has no .github/workflows folder"
      body = CodeWriteUp.body(lead: "Raises the pool.", context: nil, warning: nil, reviewed: @reviewed, change: @change, no_ci: said)
      comment = CodeWriteUp.comment(lead: "Raises it again.", warning: nil, reviewed: @reviewed, change: @change, base: "main", no_ci: said)
      answer = CodeWriteUp.answer(done: "Opened it.", warning: nil, reviewed: @reviewed, change: @change, base: "main", updating: false, no_ci: said)

      plain = "acme/api has no .github/workflows folder. With no CI, nothing beyond the checks that ran in Firefight's sandbox tested this change, " \
              "and the owner's review decides whether it is ready."
      assert_includes body, "**No CI**\n#{plain}\n\n**Files**"
      assert_includes comment, "**No CI**\n#{plain}"
      assert answer.end_with?("No CI:\n#{plain}")
      assert_not_includes CodeWriteUp.body(lead: "Raises the pool.", context: nil, warning: nil, reviewed: @reviewed, change: @change), "No CI"
    end

    test "an update's comment says what this update changed in the pull request, and a merge from the base adds no file" do
      comment = CodeWriteUp.comment(lead: "Merges main and keeps the run name fix.", warning: nil, reviewed: @reviewed, change: @change, base: "main")

      assert comment.start_with?("Merges main and keeps the run name fix.\n\nChanged in this update: `.github/workflows/release.yml`. It merges main into this branch.")
      assert_not_includes comment, "Archspec.rb", "what main brought is not this pull request's"
      assert comment.end_with?("Added by Halon in #{'c' * 12}. Review it like any other change before merging.")
      assert_no_dashes_or_semicolons comment

      merge_only = @change.with(touched: [ "Archspec.rb" ])
      assert_includes CodeWriteUp.comment(lead: "Merges main.", warning: nil, reviewed: @reviewed, change: merge_only, base: "main"),
                      "This update changes no file this pull request changes. It merges main into this branch."
    end

    test "Halon's answer has the same sections in plain text, and files the review left out are named" do
      reviewed = @reviewed.with(unreviewed: [ "db/schema.rb" ])
      answer = CodeWriteUp.answer(done: "Opened https://github.com/acme/api/pull/7 on acme/api against main.", warning: nil, reviewed: reviewed,
                                  change: @change, base: "main", updating: false)

      assert answer.start_with?("Opened https://github.com/acme/api/pull/7 on acme/api against main.\n\nChanges:\n- `.github/workflows/release.yml` (+3 -1)")
      assert_includes answer, "Could not run here:\n- `bin/rails test test/models/pool_test.rb`: no database was available."
      assert_includes answer, "Not reviewed, since the change is too large to review whole:\n- `db/schema.rb`"
      assert_no_dashes_or_semicolons answer
    end

    private

    def assert_no_dashes_or_semicolons(text)
      assert_not_includes text, "—"
      assert_not_includes text, ";"
    end
  end
end

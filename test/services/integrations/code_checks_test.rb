require "test_helper"

module Integrations
  class CodeChecksTest < ActiveSupport::TestCase
    test "a check stopped by a missing database, service or command could not run here, and one that ran and failed failed" do
      checks = CodeChecks.read([
        line("bin/rails test test/models/pool_test.rb", 1, "test_helper.rb:4: PG::ConnectionBad: connection to server on socket failed"),
        line("bundle exec rspec spec/pool_spec.rb", 1, "Redis::CannotConnectError: Error connecting to Redis on localhost:6379"),
        line("bin/rails test test/jobs/sync_test.rb", 1, "KeyError: key not found: \"SLACK_SIGNING_SECRET\""),
        line("actionlint .github/workflows/ci.yml", 127, "actionlint: command not found"),
        line("rubocop app/models/pool.rb", 1, "app/models/pool.rb:3:1: C: Layout/IndentationWidth"),
        line("bin/rails test test/models/user_test.rb", 124, "")
      ])

      assert_equal [ [ CodeChecks::COULD_NOT_RUN, "no database was available" ], [ CodeChecks::COULD_NOT_RUN, "no Redis was available" ],
                     [ CodeChecks::COULD_NOT_RUN, "secrets or settings it needs were not set" ], [ CodeChecks::COULD_NOT_RUN, "its command is not installed" ],
                     [ CodeChecks::FAILED, nil ], [ CodeChecks::TIMED_OUT, nil ] ], checks.map { |check| [ check.status, check.reason ] }
    end

    test "the review reads a check that could not run as saying nothing about the change, without what it printed" do
      checks = CodeChecks.read([ line("bin/rails test test/models/pool_test.rb", 1, "PG::ConnectionBad at /home/runner/app") ])

      summary = CodeChecks.summary(checks)

      assert_equal "- bin/rails test test/models/pool_test.rb: could not run here, since no database was available. This says nothing about the change.", summary
    end

    private

    def line(name, code, output)
      "CHECK\t#{Base64.strict_encode64(name)}\t#{code}\t#{Base64.strict_encode64(output)}"
    end
  end
end

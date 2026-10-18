require "test_helper"

module Integrations
  class ProtectedPullRequestsTest < ActiveSupport::TestCase
    URL = "https://github.com/acme/web/pull/8".freeze

    setup do
      @workspace = workspaces(:slack_workspace_one)
      @github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
      @row = @github.integration_environments.create!(base_config: { "installation_id" => "12345" })
      ResourceMap::Resource.create!(workspace: @workspace, provider: "github", account: "acme", kind: ResourceMap::KIND_REPOSITORY, external_id: "acme/web",
                                    name: "web", url: "https://github.com/acme/web", integration_environment: @row,
                                    first_seen_at: Time.current, last_seen_at: Time.current)
      @asker = workspace_memberships(:alice_workspace_one)
    end

    test "with no paths kept out, nothing is read and nothing is flagged" do
      Packs::Github.any_instance.expects(:pull_request_paths).never

      assert_empty ProtectedPullRequests.check(@workspace, [ URL ], repository: "acme/web", asked_by: @asker, via: "devin.fix_code")
    end

    test "a pull request that leaves the kept paths alone is not flagged" do
      @github.protect_paths!([ ".github/workflows/" ])
      Packs::Github.any_instance.stubs(:pull_request_paths).with(@row, repository: "acme/web", number: 8).returns([ "app/models/order.rb" ])
      Packs::Github.any_instance.expects(:flag_pull_request).never

      assert_empty ProtectedPullRequests.check(@workspace, [ URL ], repository: "acme/web", asked_by: @asker, via: "devin.fix_code")
    end

    test "a pull request touching a kept path is flagged in words, commented on and the comment is in the activity log as Halon's" do
      @github.protect_paths!([ ".github/workflows/", "infra/**" ])
      Packs::Github.any_instance.stubs(:pull_request_paths).returns([ "app/models/order.rb", ".github/workflows/deploy.yml" ])
      sent = nil
      Packs::Github.any_instance.expects(:flag_pull_request).with { |row, repository:, number:, body:| row == @row && repository == "acme/web" && number == 8 && (sent = body) }

      flags = ProtectedPullRequests.check(@workspace, [ URL ], repository: "acme/web", asked_by: @asker, via: "devin.fix_code")

      assert_equal [ format(CodeChange::PROTECTED_TOUCHED, pull_request: URL, paths: ".github/workflows/deploy.yml") ], flags.map(&:sentence)
      assert_equal format(CodeChange::PROTECTED_COMMENT, paths: ".github/workflows/deploy.yml"), sent
      logged = @workspace.ability_invocations.find_by!(source: AbilityGateway::SOURCE_CODE_AGENT, action_key: "devin.fix_code")
      assert_equal SystemAgent.investigator.id, logged.principal_id
      assert_equal Ability::Invocation::OUTCOME_SUCCESS, logged.outcome
      assert_equal({ "pull_request" => URL, "protected_paths" => [ ".github/workflows/deploy.yml" ] }, logged.params)
    end

    test "a comment the code host refuses is said with the flag, never dropped" do
      @github.protect_paths!([ ".github/workflows/" ])
      Packs::Github.any_instance.stubs(:pull_request_paths).returns([ ".github/workflows/deploy.yml" ])
      Packs::Github.any_instance.stubs(:flag_pull_request).raises(Integrations::Error, "GitHub answered 403")

      flag = ProtectedPullRequests.check(@workspace, [ URL ], repository: "acme/web", asked_by: @asker, via: "devin.fix_code").sole

      assert flag.sentence.end_with?(format(CodeChange::PROTECTED_COMMENT_FAILED, reason: "GitHub answered 403"))
    end

    test "a pull request no connected code host can read is flagged as unchecked, since unchecked is not clean" do
      @github.protect_paths!([ ".github/workflows/" ])

      flag = ProtectedPullRequests.check(@workspace, [ "https://gitlab.com/acme/web/-/merge_requests/3" ], repository: "acme/web", asked_by: @asker, via: "devin.fix_code").sole

      assert_equal format(CodeChange::PROTECTED_UNCHECKED, pull_request: "https://gitlab.com/acme/web/-/merge_requests/3",
                                                           reason: ProtectedPullRequests::NO_HOST), flag.sentence
    end

    test "a pull request whose files cannot be read is flagged as unchecked with the code host's reason, and says so on the pull request" do
      @github.protect_paths!([ ".github/workflows/" ])
      Packs::Github.any_instance.stubs(:pull_request_paths).raises(Integrations::Error, "GitHub answered 404")
      Packs::Github.any_instance.expects(:flag_pull_request).with { |row, body:, **| row == @row && body == CodeChange::PROTECTED_UNCHECKED_COMMENT }

      flag = ProtectedPullRequests.check(@workspace, [ URL ], repository: "acme/web", asked_by: @asker, via: "devin.fix_code").sole

      assert_equal format(CodeChange::PROTECTED_UNCHECKED, pull_request: URL, reason: "GitHub answered 404"), flag.sentence
    end

    test "an unchecked pull request whose comment is refused too keeps both reasons in its flag" do
      @github.protect_paths!([ ".github/workflows/" ])
      Packs::Github.any_instance.stubs(:pull_request_paths).raises(Integrations::Error, "GitHub answered 404")
      Packs::Github.any_instance.stubs(:flag_pull_request).raises(Integrations::Error, "GitHub answered 403")

      flag = ProtectedPullRequests.check(@workspace, [ URL ], repository: "acme/web", asked_by: @asker, via: "devin.fix_code").sole

      assert_equal [ format(CodeChange::PROTECTED_UNCHECKED, pull_request: URL, reason: "GitHub answered 404"),
                     format(CodeChange::PROTECTED_COMMENT_FAILED, reason: "GitHub answered 403") ].join(" "), flag.sentence
    end

    test "a pull request in another repository than the change asked for is flagged as unchecked, and never commented on" do
      @github.protect_paths!([ ".github/workflows/" ])
      ResourceMap::Resource.create!(workspace: @workspace, provider: "github", account: "acme", kind: ResourceMap::KIND_REPOSITORY, external_id: "acme/other",
                                    name: "other", url: "https://github.com/acme/other", integration_environment: @row,
                                    first_seen_at: Time.current, last_seen_at: Time.current)
      Packs::Github.any_instance.expects(:pull_request_paths).never
      Packs::Github.any_instance.expects(:flag_pull_request).never
      elsewhere = "https://github.com/acme/other/pull/9"

      flag = ProtectedPullRequests.check(@workspace, [ elsewhere ], repository: "acme/web", asked_by: @asker, via: "devin.fix_code").sole

      assert_equal format(CodeChange::PROTECTED_UNCHECKED, pull_request: elsewhere, reason: format(ProtectedPullRequests::NOT_ASKED, repository: "acme/web")),
                   flag.sentence
    end

    test "a pull request on another code host than the address the change was asked for is never read or commented on" do
      @github.protect_paths!([ ".github/workflows/" ])
      Packs::Github.any_instance.expects(:pull_request_paths).never
      Packs::Github.any_instance.expects(:flag_pull_request).never

      flag = ProtectedPullRequests.check(@workspace, [ URL ], repository: "https://gitlab.com/acme/web", asked_by: @asker, via: "devin.fix_code").sole

      assert_equal format(CodeChange::PROTECTED_UNCHECKED, pull_request: URL, reason: format(ProtectedPullRequests::NOT_ASKED, repository: "https://gitlab.com/acme/web")),
                   flag.sentence
    end

    test "an address on a repository the connection does not hold on the map is not that connection's, so nothing is read or written" do
      @github.protect_paths!([ ".github/workflows/" ])
      Packs::Github.any_instance.expects(:pull_request_paths).never
      Packs::Github.any_instance.expects(:flag_pull_request).never
      stranger = "https://github.com/stranger/web/pull/1"

      flag = ProtectedPullRequests.check(@workspace, [ stranger ], repository: "https://github.com/acme/web", asked_by: @asker, via: "devin.fix_code").sole

      assert_equal format(CodeChange::PROTECTED_UNCHECKED, pull_request: stranger, reason: ProtectedPullRequests::NO_HOST), flag.sentence
    end

    test "a connection that fails while working out an address is passed over, and the answer still comes back" do
      @github.protect_paths!([ ".github/workflows/" ])
      Packs::Github.any_instance.stubs(:pull_request_at).raises(Integrations::Error, "GitHub answered 500")

      flag = ProtectedPullRequests.check(@workspace, [ URL ], repository: "acme/web", asked_by: @asker, via: "devin.fix_code").sole

      assert_equal format(CodeChange::PROTECTED_UNCHECKED, pull_request: URL, reason: ProtectedPullRequests::NO_HOST), flag.sentence
    end
  end
end

require "test_helper"

module Integrations
  module Packs
    class BitbucketReviewPostingTest < ActiveSupport::TestCase
      REPOSITORY = "/repositories/acme/checkout".freeze

      setup do
        @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "bitbucket", name: "Bitbucket")
        @row = @integration.integration_environments.create!
        @row.store_fields!(Bitbucket::WORKSPACE => "acme")
        Bitbucket.store_credentials!(@row, Bitbucket::TOKEN => "bb-token")
        @pack = Bitbucket.new(@integration)
        BitbucketApi.any_instance.stubs(:get).with("/user").returns("account_id" => "557058:ff", "nickname" => "firefight")
      end

      test "a review comments on each line, then the summary in the conversation" do
        BitbucketApi.any_instance.stubs(:get).with("#{REPOSITORY}/pullrequests/4").returns("id" => 4, "title" => "Retries", "state" => "OPEN")
        BitbucketApi.any_instance.expects(:post).with("#{REPOSITORY}/pullrequests/4/comments", { "content" => { "raw" => "One" }, "inline" => { "path" => "a.rb", "to" => 3 } })
                    .returns("id" => 801, "links" => { "html" => { "href" => "https://bitbucket.org/acme/checkout/pull-requests/4#comment-801" } })
        BitbucketApi.any_instance.expects(:post).with("#{REPOSITORY}/pullrequests/4/comments", { "content" => { "raw" => "Summary" } }).returns("id" => 802)

        name, arguments = Bitbucket.review_call(PullRequestReviews::REVIEW, repository: "acme/checkout", number: 4, body: "Summary",
                                                                            comments: [ PullRequestReviews::LineComment.new(path: "a.rb", line: 3, body: "One") ])
        posted = Bitbucket.review_posted(PullRequestReviews::REVIEW, @pack.public_send(name, environment_row: @row, arguments: arguments).dig(Telemetry::STRUCTURED, Telemetry::FACTS))

        assert_equal [ "802", [ "801" ], [ "https://bitbucket.org/acme/checkout/pull-requests/4#comment-801" ] ], [ posted.reference, posted.comments, posted.urls ]
      end

      test "a reply names its parent, and a thread Firefight started is resolved" do
        BitbucketApi.any_instance.expects(:post).with("#{REPOSITORY}/pullrequests/4/comments", { "content" => { "raw" => "Fixed." }, "parent" => { "id" => 801 } })
                    .returns("id" => 803)
        name, arguments = Bitbucket.review_call(PullRequestReviews::REPLY, repository: "acme/checkout", number: 4, reference: "801", body: "Fixed.")
        @pack.public_send(name, environment_row: @row, arguments: arguments)

        BitbucketApi.any_instance.stubs(:get).with("#{REPOSITORY}/pullrequests/4/comments/801").returns("id" => 801, "user" => { "account_id" => "557058:ff" })
        BitbucketApi.any_instance.expects(:post).with("#{REPOSITORY}/pullrequests/4/comments/801/resolve").returns({})
        name, arguments = Bitbucket.review_call(PullRequestReviews::RESOLVE, repository: "acme/checkout", number: 4, reference: "801")
        @pack.public_send(name, environment_row: @row, arguments: arguments)
      end

      test "a comment someone else wrote is never edited" do
        BitbucketApi.any_instance.stubs(:get).with("#{REPOSITORY}/pullrequests/4/comments/900").returns("id" => 900, "user" => { "account_id" => "other", "display_name" => "Ada" })
        BitbucketApi.any_instance.expects(:put).never

        error = assert_raises(PolicyRefusal) do
          @pack.edit_pull_request_comment(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 4, "comment_id" => 900, "body" => "Mine" })
        end
        assert_includes error.message, "comment 900 is Ada's"
      end
    end
  end
end

require "test_helper"

module Integrations
  module MapEventSources
    class AzureDevopsTest < ActiveSupport::TestCase
      URL = "https://firefight.example.com/api/v1/map_events/token-1".freeze
      SUBSCRIPTIONS = "/_apis/hooks/subscriptions".freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "azure_devops", name: "Azure DevOps")
        @row = @integration.integration_environments.create!
        @row.store_fields!(Packs::AzureDevops::ORGANIZATION => "fabrikam", Packs::AzureDevops::PROJECT => %w[Shop])
        Packs::AzureDevops.store_credentials!(@row, Packs::AzureDevops::TOKEN => "pat-token")
      end

      test "a delivery carrying the secret Firefight made is Azure DevOps', and one without it is not" do
        assert AzureDevops.verify(raw_body: "{}", headers: { "x-firefight-token" => "made-secret" }, secret: "made-secret")
        assert_not AzureDevops.verify(raw_body: "{}", headers: { "x-firefight-token" => "guessed" }, secret: "made-secret")
        assert_not AzureDevops.verify(raw_body: "{}", headers: {}, secret: "made-secret")
        assert_not AzureDevops.verify(raw_body: "{}", headers: { "x-firefight-token" => "" }, secret: nil)
      end

      test "a push to the default branch re-reads its repository, and a push to another branch nothing" do
        event = AzureDevops.events(push("refs/heads/main"), headers: {}).sole
        assert_equal [ "event-1", ResourceMap::Event::UPDATED ], [ event.id, event.action ]
        assert_equal ResourceMap::Scope.new(kind: ResourceMap::KIND_REPOSITORY, external_id: "Shop/checkout"), event.scope

        assert_empty AzureDevops.events(push("refs/heads/feature"), headers: {})
      end

      test "a repository created or deleted is read again by its name, a rename reads every repository, and other events change nothing" do
        created = AzureDevops.events({ "id" => "e", "eventType" => "git.repo.created",
                                       "resource" => { "repository" => { "name" => "new", "project" => { "name" => "Shop" } } } }, headers: {}).sole
        assert_equal [ ResourceMap::Event::ADDED, "Shop/new" ], [ created.action, created.scope.external_id ]

        deleted = AzureDevops.events({ "id" => "e", "eventType" => "git.repo.deleted", "resource" => { "repositoryName" => "old", "project" => { "name" => "Shop" } } }, headers: {}).sole
        assert_equal [ ResourceMap::Event::REMOVED, "Shop/old" ], [ deleted.action, deleted.scope.external_id ]

        assert AzureDevops.events({ "id" => "e", "eventType" => "git.repo.renamed", "resource" => {} }, headers: {}).sole.rescope?
        assert_empty AzureDevops.events({ "id" => "e", "eventType" => "build.complete", "resource" => {} }, headers: {})
      end

      test "a run, stage, job, approval or release moving wakes watches, and a push does not" do
        %w[build.complete ms.vss-pipelines.run-state-changed-event ms.vss-pipelines.stage-state-changed-event ms.vss-pipelines.job-state-changed-event
           ms.vss-pipelinechecks-events.approval-pending ms.azure-devops-release.deployment-completed-event].each do |type|
          assert AzureDevops.wakes?({ "eventType" => type }, headers: {}), type
        end
        assert_not AzureDevops.wakes?({ "eventType" => "git.push" }, headers: {})
      end

      test "a completed run is a CI run that ended, and the branches a push moved are named for the handbook" do
        run = AzureDevops.runs_ended({ "eventType" => "build.complete", "resource" => {
          "id" => 7, "result" => "failed", "definition" => { "name" => "checkout-ci" }, "project" => { "name" => "Shop" }, "repository" => { "name" => "checkout" },
          "sourceBranch" => "refs/heads/main", "sourceVersion" => "a" * 40, "_links" => { "web" => { "href" => "https://dev.azure.com/fabrikam/Shop/_build/results?buildId=7" } }
        } }, headers: {}).sole
        assert_equal [ RunsEnded::KIND_CI, RunsEnded::OUTCOME_FAILED, "build:7:failed", "checkout-ci", "Shop/checkout", "main" ],
                     [ run.kind, run.outcome, run.reference, run.name, run.place, run.ref ]
        assert_empty AzureDevops.runs_ended({ "eventType" => "build.complete", "resource" => { "id" => 7, "result" => "none" } }, headers: {})

        assert_equal [ RepositoryDocuments::Push.new(repository: "Shop/checkout", branch: "main") ], AzureDevops.branch_pushes(push("refs/heads/main"), headers: {})
      end

      test "each project gets a subscription per event sending Firefight's secret, after Firefight's own from before at this address is taken back" do
        AzureDevopsApi.any_instance.stubs(:get).with("/_apis/projects/Shop").returns("id" => "project-guid")
        AzureDevopsApi.any_instance.stubs(:get).with(SUBSCRIPTIONS, { "consumerId" => "webHooks", "consumerActionId" => "httpRequest" })
                      .returns("value" => [ { "id" => "old", "consumerInputs" => { "url" => URL }, "publisherInputs" => { "projectId" => "project-guid" } },
                                            { "id" => "theirs", "consumerInputs" => { "url" => "https://example.com/hook" }, "publisherInputs" => { "projectId" => "project-guid" } } ])
        AzureDevopsApi.any_instance.expects(:delete).with("#{SUBSCRIPTIONS}/old").once
        sent = []
        AzureDevopsApi.any_instance.stubs(:post).with { |path, body| path == SUBSCRIPTIONS && sent << body }.returns({ "id" => "sub" })

        webhook = AzureDevops.register(@row, url: URL)

        assert_equal AzureDevops::EVENTS.keys, sent.map { |body| body["eventType"] }
        secret = webhook.secret
        assert_match(/\A\h{64}\z/, secret)
        push = sent.find { |body| body["eventType"] == "git.push" }
        assert_equal({ "publisherId" => "tfs", "eventType" => "git.push", "resourceVersion" => "1.0", "consumerId" => "webHooks", "consumerActionId" => "httpRequest",
                       "publisherInputs" => { "projectId" => "project-guid" }, "consumerInputs" => { "url" => URL, "httpHeaders" => "X-Firefight-Token:#{secret}" } }, push)
        assert_not sent.find { |body| body["eventType"] == "ms.vss-pipelines.run-state-changed-event" }.key?("resourceVersion")
        assert_equal({ "Shop" => [ "sub" ] * AzureDevops::EVENTS.size }, JSON.parse(webhook.id))
        assert_equal [ "Shop" ], webhook.scopes
      end

      test "a token without a project administrator's rights is told why" do
        AzureDevopsApi.any_instance.stubs(:get).with("/_apis/projects/Shop").returns("id" => "project-guid")
        AzureDevopsApi.any_instance.stubs(:get).with(SUBSCRIPTIONS, anything).returns("value" => [])
        AzureDevopsApi.any_instance.stubs(:post).raises(AzureDevopsApi::Refused, "Azure DevOps answered 403: TF50309")

        error = assert_raises(MapEventSource::Refused) { AzureDevops.register(@row, url: URL) }
        assert_match "project administrator", error.message
      end

      test "a subscription Azure DevOps switched off or no longer has is registered again, and ones still sending are left" do
        @row.update!(map_events_webhook_id: { "Shop" => %w[one] * AzureDevops::EVENTS.size }.to_json)
        AzureDevopsApi.any_instance.stubs(:get).with("#{SUBSCRIPTIONS}/one").returns("status" => "enabled")
        assert_not AzureDevops.register_again?(@row, url: URL)

        AzureDevopsApi.any_instance.stubs(:get).with("#{SUBSCRIPTIONS}/one").returns("status" => "disabledBySystem")
        assert AzureDevops.register_again?(@row, url: URL)

        AzureDevopsApi.any_instance.stubs(:get).with("#{SUBSCRIPTIONS}/one").raises(AzureDevopsApi::NotFound, "404")
        assert AzureDevops.register_again?(@row, url: URL)

        @row.update!(map_events_webhook_id: { "Shop" => %w[one] }.to_json)
        AzureDevopsApi.any_instance.stubs(:get).with("#{SUBSCRIPTIONS}/one").returns("status" => "enabled")
        assert AzureDevops.register_again?(@row, url: URL), "one made before an event was followed misses it"
      end

      test "removing takes back every subscription, one already gone included" do
        AzureDevopsApi.any_instance.expects(:delete).with("#{SUBSCRIPTIONS}/a").once
        AzureDevopsApi.any_instance.expects(:delete).with("#{SUBSCRIPTIONS}/b").raises(AzureDevopsApi::NotFound, "404")

        AzureDevops.remove(@row, { "Shop" => %w[a b] }.to_json)
      end

      private

      def push(ref)
        { "id" => "event-1", "eventType" => "git.push",
          "resource" => { "refUpdates" => [ { "name" => ref, "oldObjectId" => "0" * 40, "newObjectId" => "a" * 40 } ],
                          "repository" => { "name" => "checkout", "project" => { "name" => "Shop" }, "defaultBranch" => "refs/heads/main" } } }
      end
    end
  end
end

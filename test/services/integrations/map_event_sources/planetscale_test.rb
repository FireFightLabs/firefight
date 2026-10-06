require "test_helper"

module Integrations
  module MapEventSources
    class PlanetscaleTest < ActiveSupport::TestCase
      # The branch.ready payload PlanetScale's reference shows (planetscale.com/docs/api/webhook-events, Branch ready), cut
      # to the fields read, and a deploy request's.
      BRANCH_READY = { "timestamp" => 1_698_252_879, "event" => "branch.ready", "organization" => "myorg", "database" => "example_database",
                       "resource" => { "id" => "ecrmjy2f4a5o", "type" => "Branch", "name" => "dev", "state" => "ready", "production" => false } }.freeze
      DEPLOY_REQUEST = { "timestamp" => 1_698_252_899, "event" => "deploy_request.schema_applied", "organization" => "myorg",
                         "database" => "example_database",
                         "resource" => { "id" => "4xsz0ql82y4n", "type" => "DeployRequest", "branch" => "dev", "into_branch" => "main", "branch_deleted" => false } }.freeze
      SECRET = "8e46bd50ca092655b1efdfca329f0d79eb976714030a8bfa031397eb0d1cb433".freeze

      test "a delivery whose X-PlanetScale-Signature is the HMAC-SHA256 hex digest of its body is PlanetScale's, and no other is" do
        body = BRANCH_READY.to_json
        signature = OpenSSL::HMAC.hexdigest("SHA256", SECRET, body)

        assert Planetscale.verify(raw_body: body, headers: { "X-PlanetScale-Signature" => signature }, secret: SECRET)
        assert_not Planetscale.verify(raw_body: body.sub("dev", "prod"), headers: { "X-PlanetScale-Signature" => signature }, secret: SECRET)
        assert_not Planetscale.verify(raw_body: body, headers: { "X-PlanetScale-Signature" => OpenSSL::HMAC.hexdigest("SHA256", "another", body) }, secret: SECRET)
        assert_not Planetscale.verify(raw_body: body, headers: {}, secret: SECRET)
        assert_not Planetscale.verify(raw_body: body, headers: { "X-PlanetScale-Signature" => OpenSSL::HMAC.hexdigest("SHA256", "", body) }, secret: nil)
      end

      test "a branch event names the branch, a deploy request the branch it deploys into, and a closed one that deleted its branch that branch" do
        ready = Planetscale.events(BRANCH_READY, headers: {}).sole
        assert_equal ResourceMap::Scope.new(account: "myorg", kind: ResourceMap::KIND_BRANCH, external_id: "example_database/dev"), ready.scope
        assert_equal [ ResourceMap::Event::ADDED, Time.zone.at(1_698_252_879) ], [ ready.action, ready.at ]
        assert_equal ready.id, Planetscale.events(JSON.parse(BRANCH_READY.to_json), headers: {}).sole.id, "a redelivery is the same event"

        sleeping = Planetscale.events(BRANCH_READY.merge("event" => "branch.sleeping"), headers: {}).sole
        assert_equal ResourceMap::Event::UPDATED, sleeping.action

        applied = Planetscale.events(DEPLOY_REQUEST, headers: {}).sole
        assert_equal "example_database/main", applied.scope.external_id
        closed = DEPLOY_REQUEST.merge("event" => "deploy_request.closed", "resource" => DEPLOY_REQUEST["resource"].merge("branch_deleted" => true))
        assert_equal "example_database/dev", Planetscale.events(closed, headers: {}).sole.scope.external_id

        %w[webhook.test branch.anomaly backup.succeeded keyspace.storage].each do |type|
          assert_empty Planetscale.events(BRANCH_READY.merge("event" => type), headers: {}), "#{type} changes nothing on the map"
        end
        assert_empty Planetscale.events(BRANCH_READY.except("database"), headers: {})
      end

      test "an admin adds a webhook to each database, each with a secret of its own, so every one saved counts" do
        assert Planetscale.many_secrets?
        assert_not Planetscale.registers?
        assert_match "hourly sweep", Planetscale.limits
        assert Planetscale::EVENTS.all? { |type| Planetscale.setup_steps.join(" ").include?(type) }
      end
    end
  end
end

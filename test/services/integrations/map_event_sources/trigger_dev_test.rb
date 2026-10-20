require "test_helper"

module Integrations
  module MapEventSources
    class TriggerDevTest < ActiveSupport::TestCase
      SECRET = "whsec-alerts".freeze
      # The alert webhook payloads Trigger.dev documents (docs/troubleshooting-alerts.mdx, Alert webhooks), cut to the fields read.
      DEPLOYED = {
        "id" => "evt_1", "created" => "2026-10-01T10:00:00Z", "webhookVersion" => "2025-01-01", "type" => "alert.deployment.success",
        "object" => { "deployment" => { "id" => "deployment_1", "status" => "DEPLOYED", "version" => "20261001.1", "shortCode" => "abc" },
                      "environment" => { "slug" => "prod" }, "project" => { "ref" => "proj_acme", "name" => "Acme" },
                      "git" => { "branch" => "main", "commitSha" => "1a2b3c4" } }
      }.freeze
      RUN_FAILED = { "id" => "evt_2", "created" => "2026-10-01T10:01:00Z", "type" => "alert.run.failed",
                     "object" => { "task" => { "id" => "send-email" }, "run" => { "id" => "run_1", "status" => "FAILED" } } }.freeze

      test "a delivery signed with the alert's secret as an HMAC-SHA256 hex digest of its body is Trigger.dev's, and no other is" do
        body = DEPLOYED.to_json
        signature = OpenSSL::HMAC.hexdigest("SHA256", SECRET, body)

        assert TriggerDev.verify(raw_body: body, headers: { TriggerDev::SIGNATURE_HEADER => signature }, secret: SECRET)
        assert_not TriggerDev.verify(raw_body: body.sub("prod", "dev"), headers: { TriggerDev::SIGNATURE_HEADER => signature }, secret: SECRET)
        assert_not TriggerDev.verify(raw_body: body, headers: {}, secret: SECRET)
        assert_not TriggerDev.verify(raw_body: body, headers: { TriggerDev::SIGNATURE_HEADER => signature }, secret: nil)
        assert_equal TriggerDev, Provider.for(Packs::TriggerDev::PROVIDER_KEY).map_events
        assert TriggerDev.many_secrets?
        assert_not TriggerDev.registers?
      end

      test "a deployment that succeeded reads the environment again, and every alert wakes a watch" do
        event = TriggerDev.events(DEPLOYED, headers: {}).sole
        assert_equal [ "evt_1", ResourceMap::Event::RESCOPE, Time.utc(2026, 10, 1, 10) ], [ event.provider_id, event.action, event.at ]
        assert_empty TriggerDev.events(RUN_FAILED, headers: {})

        assert TriggerDev.wakes?(RUN_FAILED, headers: {})
        assert TriggerDev.wakes?(DEPLOYED.merge("type" => "alert.error"), headers: {})
        assert_not TriggerDev.wakes?({ "type" => "something.else" }, headers: {})
      end

      test "a deployment that succeeded or failed is a deploy that ended, and a failed run is not" do
        run = TriggerDev.runs_ended(DEPLOYED, headers: {}).sole
        assert_equal [ RunsEnded::KIND_DEPLOY, RunsEnded::OUTCOME_SUCCEEDED, "deploy:deployment_1:#{RunsEnded::OUTCOME_SUCCEEDED}", "20261001.1", "proj_acme", "main", "1a2b3c4", "prod" ],
                     [ run.kind, run.outcome, run.reference, run.name, run.place, run.ref, run.commit, run.environment ]
        assert_equal RunsEnded::OUTCOME_FAILED, TriggerDev.runs_ended(DEPLOYED.merge("type" => "alert.deployment.failed"), headers: {}).sole.outcome
        assert_empty TriggerDev.runs_ended(RUN_FAILED, headers: {})
      end
    end
  end
end

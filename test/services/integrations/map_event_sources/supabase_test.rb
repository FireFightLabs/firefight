require "test_helper"

module Integrations
  module MapEventSources
    class SupabaseTest < ActiveSupport::TestCase
      # The envelope Supabase's docs show (supabase.com/docs/guides/platform/webhooks/events, Event envelope).
      SAMPLE = { "id" => "019f3c9c-c758-766d-acb2-94eb089b3f69", "type" => "v1.project.paused", "timestamp" => "2026-07-07T12:45:35.449Z",
                 "payload" => { "project_ref" => "abcdefghijklmnoprstu", "organization_slug" => "acme", "actor" => nil } }.freeze

      test "a delivery signed as Standard Webhooks says is Supabase's, with a whsec_ secret or a plain one, and a stale or forged one is not" do
        body = SAMPLE.to_json
        plain = "a plain signing secret"
        encoded = "whsec_#{Base64.strict_encode64('a base64 signing key')}"

        assert Supabase.verify(raw_body: body, headers: signed(body, plain), secret: plain)
        assert Supabase.verify(raw_body: body, headers: signed(body, Base64.decode64(encoded.delete_prefix("whsec_"))), secret: encoded)
        assert_not Supabase.verify(raw_body: body, headers: signed(body, plain), secret: "another secret")
        assert_not Supabase.verify(raw_body: body.sub("paused", "restored"), headers: signed(body, plain), secret: plain)
        assert_not Supabase.verify(raw_body: body, headers: signed(body, plain, at: 6.minutes.ago), secret: plain)
        assert_not Supabase.verify(raw_body: body, headers: signed(body, plain).except("webhook-signature"), secret: plain)
        assert_not Supabase.verify(raw_body: body, headers: signed(body, plain), secret: nil)
      end

      test "a project event names the project, a branch its parent, and a branch removed or a project moved sweeps the connection" do
        paused = Supabase.events(SAMPLE, headers: {}).sole
        assert_equal [ SAMPLE["id"], ResourceMap::Event::UPDATED, Time.iso8601(SAMPLE["timestamp"]) ], [ paused.id, paused.action, paused.at ]
        assert_equal ResourceMap::Scope.new(account: "acme", kind: ResourceMap::KIND_DATABASE, external_id: "abcdefghijklmnoprstu"), paused.scope

        assert_equal ResourceMap::Event::ADDED, Supabase.events(SAMPLE.merge("type" => "v1.project.created"), headers: {}).sole.action
        branch = Supabase.events(SAMPLE.merge("type" => "v1.project.branch.created", "payload" => SAMPLE["payload"].merge("branch" => { "ref" => "branchrefbranchrefbr" })), headers: {}).sole
        assert_equal "abcdefghijklmnoprstu", branch.scope.external_id
        Supabase::RESCOPE_EVENTS.each { |type| assert Supabase.events(SAMPLE.merge("type" => type), headers: {}).sole.rescope? }

        assert_empty Supabase.events(SAMPLE.merge("type" => "v1.organization.member.added", "payload" => SAMPLE["payload"].merge("project_ref" => nil)), headers: {})
        assert_empty Supabase.events(SAMPLE.merge("type" => "v1.project.backup.started"), headers: {})
        assert_empty Supabase.events(SAMPLE.merge("payload" => SAMPLE["payload"].merge("is_test" => true)), headers: {})
      end

      test "an admin creates the endpoint with the Management API and saves the secret they chose, and Supabase's early access is said" do
        assert_not Supabase.registers?
        assert_not Supabase.many_secrets?
        assert Supabase::EVENTS.all? { |type| Supabase.setup_steps.join(" ").include?(type) }
        assert_includes Supabase.by_hand_note, "early access"
      end

      private

      def signed(body, key, at: Time.current)
        stamp = at.to_i.to_s
        { "webhook-id" => SAMPLE["id"], "webhook-timestamp" => stamp,
          "webhook-signature" => "v1,#{Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', key, "#{SAMPLE['id']}.#{stamp}.#{body}"))}" }
      end
    end
  end
end

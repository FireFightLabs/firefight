require "test_helper"

module Integrations
  module SourceLinks
    class PagerdutyTest < ActiveSupport::TestCase
      setup do
        @links = Pagerduty.new(nil)
      end

      # Shaped as PagerDuty's own example of an incident and the references it carries.
      INCIDENT = {
        "id" => "PGR0VU2", "html_url" => "https://acme.pagerduty.com/incidents/PGR0VU2", "title" => "A little bump in the road",
        "service" => { "html_url" => "https://acme.pagerduty.com/services/PF9KMXH", "id" => "PF9KMXH" },
        "assignees" => [ { "html_url" => "https://acme.pagerduty.com/users/PTUXL6G" } ],
        "escalation_policy" => { "html_url" => "https://acme.pagerduty.com/escalation_policies/PUS0KTE" }
      }.freeze

      test "an answer about one incident links to the incident, not the service or people it names" do
        link = @links.link(tool_name: "browse_incidents", arguments: { "action" => "get" }, text: INCIDENT.to_json)

        assert_equal "PagerDuty", link.provider
        assert_equal "https://acme.pagerduty.com/incidents/PGR0VU2", link.url
      end

      test "a schedule links to itself, and an EU account's address is used as PagerDuty gave it" do
        schedule = { "html_url" => "https://acme.eu.pagerduty.com/schedules/PI7DH85", "users" => [ { "html_url" => "https://acme.eu.pagerduty.com/users/PXPGF42" } ] }

        assert_equal "https://acme.eu.pagerduty.com/schedules/PI7DH85", @links.link(tool_name: "browse_schedules", arguments: {}, text: schedule.to_json).url
      end

      test "PagerDuty's two service regions each reach their own server and app" do
        regions = IntegrationProvider.find(Providers::Pagerduty.key).regions

        assert_equal [ "https://mcp.pagerduty.com/mcp", "https://mcp.eu.pagerduty.com/mcp" ], regions.map(&:server_url)
        assert_equal [ "https://app.pagerduty.com", "https://app.eu.pagerduty.com" ], regions.map(&:site)
      end

      test "a list of several, or an answer with no PagerDuty address, gets no link" do
        two = [ INCIDENT, INCIDENT.merge("html_url" => "https://acme.pagerduty.com/incidents/Q1R2S3") ].to_json

        assert_nil @links.link(tool_name: "browse_incidents", arguments: {}, text: two)
        assert_nil @links.link(tool_name: "browse_incidents", arguments: {}, text: %({"incidents":[]}))
        assert_nil @links.link(tool_name: "browse_incidents", arguments: {}, text: "see https://evil.example/incidents/PGR0VU2")
      end
    end
  end
end

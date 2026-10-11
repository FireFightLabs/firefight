require "test_helper"

class AlertProviders::PagerdutyTest < ActiveSupport::TestCase
  setup do
    @source = AlertSource.create!(workspace: workspaces(:slack_workspace_one), name: "PagerDuty", provider: AlertSource::PROVIDER_PAGERDUTY)
  end

  # PagerDuty's own example of a v3 webhook, from its developer documentation.
  def pagerduty_payload(event_type: "incident.triggered", event_id: "5ac64822-4adc-4fda-ade0-410becf0de4f")
    {
      "event" => {
        "id" => event_id, "event_type" => event_type, "resource_type" => "incident", "occurred_at" => "2020-10-02T18:45:22.169Z",
        "agent" => { "html_url" => "https://acme.pagerduty.com/users/PLH1HKV", "id" => "PLH1HKV", "type" => "user_reference" },
        "client" => { "name" => "PagerDuty" },
        "data" => {
          "id" => "PGR0VU2", "type" => "incident", "self" => "https://api.pagerduty.com/incidents/PGR0VU2",
          "html_url" => "https://acme.pagerduty.com/incidents/PGR0VU2", "number" => 2, "status" => "triggered",
          "incident_key" => "d3640fbd41094207a1c11e58e46b1662", "created_at" => "2020-04-09T15:16:27Z",
          "title" => "A little bump in the road",
          "service" => { "html_url" => "https://acme.pagerduty.com/services/PF9KMXH", "id" => "PF9KMXH", "summary" => "API Service", "type" => "service_reference" },
          "teams" => [ { "id" => "PFCVPS0", "summary" => "Engineering", "type" => "team_reference" } ],
          "priority" => { "id" => "PSO75BM", "summary" => "P1", "type" => "priority_reference" },
          "urgency" => "high"
        }
      }
    }
  end

  test "verifies the token the subscription sends in its custom header" do
    assert AlertProviders::Pagerduty.verify(headers: { "X-Firefight-Token" => @source.secret_token }, raw_body: "{}", source: @source)
    assert_not AlertProviders::Pagerduty.verify(headers: { "X-Firefight-Token" => "wrong" }, raw_body: "{}", source: @source)
    assert_not AlertProviders::Pagerduty.verify(headers: {}, raw_body: "{}", source: @source)
  end

  test "a triggered incident fires, keyed on the incident, with its service, team and priority" do
    item = AlertProviders::Pagerduty.normalize(pagerduty_payload, source: @source).sole
    fields = item[:fields]

    assert_equal "5ac64822-4adc-4fda-ade0-410becf0de4f", fields["external_id"]
    assert_equal "PGR0VU2", fields["fingerprint"]
    assert_equal Alert::STATUS_FIRING, fields["status"]
    assert_equal "A little bump in the road", fields["title"]
    assert_equal "PagerDuty incident #2, https://acme.pagerduty.com/incidents/PGR0VU2", fields["description"]
    assert_equal "API Service", fields["service"]
    assert_equal "Engineering", fields["team"]
    assert_equal "P1", fields["severity_raw"]
    assert_equal "https://acme.pagerduty.com/incidents/PGR0VU2", fields["url"]
  end

  test "resolved resolves the same alert, and urgency stands in when there is no priority" do
    payload = pagerduty_payload(event_type: "incident.resolved", event_id: "e2")
    payload["event"]["data"].delete("priority")
    fields = AlertProviders::Pagerduty.normalize(payload, source: @source).sole[:fields]

    assert_equal Alert::STATUS_RESOLVED, fields["status"]
    assert_equal "PGR0VU2", fields["fingerprint"]
    assert_equal "high", fields["severity_raw"]
  end

  test "an acknowledgement or the ping a new subscription sends is ignored, and something that is not a webhook is not" do
    acknowledged = pagerduty_payload(event_type: "incident.acknowledged")
    ping = { "event" => { "id" => "p1", "event_type" => "pagey.ping", "resource_type" => "pagey", "data" => { "message" => "Hello from your friend Pagey!", "type" => "ping" } } }

    [ acknowledged, ping ].each do |payload|
      assert_empty AlertProviders::Pagerduty.normalize(payload, source: @source)
      assert AlertProviders::Pagerduty.ignored?(payload)
    end
    assert_not AlertProviders::Pagerduty.ignored?({ "title" => "not PagerDuty" })
    assert_not AlertProviders::Pagerduty.ignored?(pagerduty_payload)
  end

  test "an acknowledgement, an escalation and a resolve are what happened to a page, by a person or by automation" do
    acknowledged = AlertProviders::Pagerduty.page_event(pagerduty_payload(event_type: "incident.acknowledged", event_id: "e3"))
    assert_equal [ "e3", "PGR0VU2", "d3640fbd41094207a1c11e58e46b1662", Integrations::Paging::EVENT_ACKNOWLEDGED, true ],
                 [ acknowledged.id, acknowledged.external_id, acknowledged.key, acknowledged.kind, acknowledged.by_person ]
    assert_nil acknowledged.actor_email, "PagerDuty names who did it but gives no email"

    escalated = pagerduty_payload(event_type: "incident.escalated")
    escalated["event"]["data"]["assignees"] = [ { "id" => "PTUXL6G", "summary" => "Bob Ruiz", "type" => "user_reference" } ]
    assert_equal "To Bob Ruiz.", AlertProviders::Pagerduty.page_event(escalated).note

    resolved = pagerduty_payload(event_type: "incident.resolved")
    resolved["event"]["agent"] = { "id" => "PSVC", "summary" => "Datadog", "type" => "service_reference" }
    assert_not AlertProviders::Pagerduty.page_event(resolved).by_person
    assert_equal Integrations::Paging::EVENT_RESOLVED, AlertProviders::Pagerduty.page_event(resolved).kind
  end

  test "a note names the incident it was added to, and the ping and a trigger are not about a page" do
    annotated = { "event" => { "id" => "e4", "event_type" => "incident.annotated", "agent" => { "summary" => "Ana Diaz", "type" => "user_reference" },
                               "data" => { "type" => "incident_note", "id" => "P2LA89X", "content" => "I sure am glad we are using PagerDuty!",
                                           "incident" => { "id" => "PGR0VU2", "type" => "incident_reference" } } } }

    event = AlertProviders::Pagerduty.page_event(annotated)

    assert_equal [ "PGR0VU2", nil, Integrations::Paging::EVENT_NOTED, "I sure am glad we are using PagerDuty!", "Ana Diaz" ],
                 [ event.external_id, event.key, event.kind, event.note, event.actor_name ]
    assert_nil AlertProviders::Pagerduty.page_event(pagerduty_payload)
    assert_nil AlertProviders::Pagerduty.page_event({ "title" => "not PagerDuty" })
    assert_equal "d3640fbd41094207a1c11e58e46b1662", AlertProviders::Pagerduty.page_key(pagerduty_payload)
  end
end

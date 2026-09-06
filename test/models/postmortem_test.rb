require "test_helper"

class PostmortemTest < ActiveSupport::TestCase
  test "belongs to incident" do
    postmortem = postmortems(:postmortem_resolved_ws1)
    assert_equal incidents(:resolved_minor_ws1), postmortem.incident
  end

  test "belongs to generated_by membership" do
    postmortem = postmortems(:postmortem_resolved_ws1)
    assert_equal workspace_memberships(:alice_workspace_one), postmortem.generated_by
  end

  test "validates title presence" do
    postmortem = Postmortem.new(
      incident: incidents(:resolved_minor_ws1),
      generated_by: workspace_memberships(:alice_workspace_one),
      content: { "sections" => [] },
      status: Postmortem::STATUS_DRAFT
    )
    assert_not postmortem.valid?
    assert_includes postmortem.errors[:title], "can't be blank"
  end

  test "validates content presence" do
    postmortem = Postmortem.new(
      incident: incidents(:resolved_minor_ws1),
      generated_by: workspace_memberships(:alice_workspace_one),
      title: "Test",
      status: Postmortem::STATUS_DRAFT
    )
    assert_not postmortem.valid?
    assert_includes postmortem.errors[:content], "can't be blank"
  end

  test "validates status inclusion" do
    postmortem = postmortems(:postmortem_resolved_ws1)
    postmortem.status = "invalid"
    assert_not postmortem.valid?
  end

  test "html_content returns stored html" do
    postmortem = postmortems(:postmortem_resolved_ws1)
    postmortem.content = { "html" => "<h2>Test</h2>" }
    assert_equal "<h2>Test</h2>", postmortem.html_content
  end

  test "html_content falls back to legacy sections" do
    postmortem = postmortems(:postmortem_resolved_ws1)
    assert_not_nil postmortem.html_content
  end

  test "update_content! strips script tags and event handlers" do
    postmortem = postmortems(:postmortem_resolved_ws1)
    member = workspace_memberships(:alice_workspace_one)

    postmortem.update_content!(
      '<p>Hello</p><script>alert(1)</script><img src=x onerror=alert(2)><a href="javascript:bad()">x</a>',
      by: member
    )

    html = postmortem.reload.content["html"]
    assert_includes html, "<p>Hello</p>"
    assert_not_includes html, "<script"
    assert_not_includes html, "onerror"
    assert_not_includes html, "javascript:"
  end

  test "update_content! preserves allowed formatting tags" do
    postmortem = postmortems(:postmortem_resolved_ws1)
    member = workspace_memberships(:alice_workspace_one)

    input = "<h2>Heading</h2><p><strong>bold</strong> and <em>italic</em></p><ul><li>one</li></ul>"
    postmortem.update_content!(input, by: member)

    html = postmortem.reload.content["html"]
    %w[<h2> <strong> <em> <ul> <li>].each { |tag| assert_includes html, tag }
  end

  test "incident can only have one postmortem" do
    existing = postmortems(:postmortem_resolved_ws1)
    duplicate = Postmortem.new(
      incident: existing.incident,
      generated_by: existing.generated_by,
      title: "Duplicate",
      content: { "sections" => [] }
    )
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save! }
  end

  test "complete_generation! renders every heading, the timeline from the record, and a placeholder where the model had nothing" do
    member = workspace_memberships(:alice_workspace_one)
    incident = Incident.create!(
      workspace: workspaces(:slack_workspace_one), declared_by: member,
      incident_status: incident_statuses(:resolved_ws1), incident_severity: incident_severities(:minor_ws1),
      name: "Sparse incident", is_private: false, resolved_at: Time.current, source: Incident::SOURCE_SLACK
    )
    incident.record_change!(IncidentEvent::INCIDENT_RESOLVED, by: member)
    draft = FirefightAi::PostmortemGenerator::Draft.new(
      title: "INC Postmortem: Sparse", summary: nil,
      sections: { "introduction" => "Declared and resolved within a minute." }, model: "gpt-4o"
    )

    postmortem = Postmortem.complete_generation!(incident, draft, generated_by: member)

    html = postmortem.html_content
    Postmortem::SECTION_HEADINGS.each_value { |heading| assert_includes html, "<h2>#{heading}</h2>" }
    assert_includes html, "Declared and resolved within a minute."
    assert_includes html, "resolved the incident"
    assert_equal Postmortem::SECTION_KEYS.size - 2, html.scan(Postmortem::EMPTY_SECTION_PLACEHOLDER).size
    assert_nil postmortem.summary
  end

  test "start_blank! turns a failed placeholder into the blank document" do
    member = workspace_memberships(:alice_workspace_one)
    incident = Incident.create!(
      workspace: workspaces(:slack_workspace_one), declared_by: member,
      incident_status: incident_statuses(:resolved_ws1), incident_severity: incident_severities(:minor_ws1),
      name: "Failed then blank", is_private: false, resolved_at: Time.current, source: Incident::SOURCE_SLACK
    )
    placeholder = Postmortem.start_generation!(incident, by: member)
    placeholder.mark_generation_failed!("TerminalError")

    assert_no_difference "Postmortem.count" do
      Postmortem.start_blank!(incident, by: member)
    end

    placeholder.reload
    assert_nil placeholder.generation_state
    assert_nil placeholder.generation_error
    assert_equal "", placeholder.html_content.to_s
    assert_equal "#{incident.identifier} Postmortem: #{incident.name}", placeholder.title
  end
end

require "test_helper"

class PostmortemTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities,
           :postmortems

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
end

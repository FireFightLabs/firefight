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

  test "sections returns content sections array" do
    postmortem = postmortems(:postmortem_resolved_ws1)
    assert_kind_of Array, postmortem.sections
    assert postmortem.sections.any?
  end

  test "sections returns empty array when content has no sections" do
    postmortem = postmortems(:postmortem_resolved_ws1)
    postmortem.content = {}
    assert_equal [], postmortem.sections
  end

  test "section finds by key" do
    postmortem = postmortems(:postmortem_resolved_ws1)
    section = postmortem.section(:summary)
    assert_equal "summary", section["key"]
    assert_equal "Summary", section["heading"]
  end

  test "section returns nil for unknown key" do
    postmortem = postmortems(:postmortem_resolved_ws1)
    assert_nil postmortem.section(:nonexistent)
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

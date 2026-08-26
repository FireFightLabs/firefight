require "test_helper"

# Replacing the body is the one postmortem write that can throw away somebody
# else's work, so it is the one that asks which version you read.
class PostmortemContentVersionTest < ActiveSupport::TestCase
  setup do
    @postmortem = postmortems(:postmortem_resolved_ws1)
    @member = workspace_memberships(:alice_workspace_one)
    @other = workspace_memberships(:bob_workspace_one)
  end

  test "a write against the version that was read wins" do
    version = @postmortem.content_version

    @postmortem.update_content!("<p>What happened</p>", by: @member, expected_version: version)

    assert_equal "<p>What happened</p>", @postmortem.reload.html_content
    assert_equal version + 1, @postmortem.content_version
  end

  # An agent that read the document, then a person who edited it before the
  # agent got round to writing. The agent loses, not the person.
  test "a write against a version somebody has replaced is refused" do
    stale = @postmortem.content_version
    @postmortem.update_content!("<p>Typed by a person</p>", by: @other, expected_version: stale)

    assert_raises(Postmortem::StaleContent) do
      Postmortem.find(@postmortem.id)
        .update_content!("<p>Written by an agent</p>", by: @member, expected_version: stale)
    end

    assert_equal "<p>Typed by a person</p>", @postmortem.reload.html_content
  end

  test "a refused write leaves no revision behind" do
    stale = @postmortem.content_version
    @postmortem.update_content!("<p>First</p>", by: @other, expected_version: stale)
    before = @postmortem.postmortem_updates.count

    assert_raises(Postmortem::StaleContent) do
      Postmortem.find(@postmortem.id).update_content!("<p>Second</p>", by: @member, expected_version: stale)
    end

    assert_equal before, @postmortem.postmortem_updates.count
  end

  # Status is a separate field, so moving one to in_review while somebody is
  # typing is not a conflict and must not be treated as one.
  test "a status change does not move the content version" do
    version = @postmortem.content_version

    @postmortem.update_status!(Postmortem::STATUS_IN_REVIEW, by: @member)

    assert_equal version, @postmortem.reload.content_version
  end
end

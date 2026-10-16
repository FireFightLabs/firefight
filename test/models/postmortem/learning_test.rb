require "test_helper"

class Postmortem::LearningTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "a postmortem marked completed is read against what the incident taught, once, and other changes are not" do
    incident = incidents(:active_critical_ws1)
    member = workspace_memberships(:alice_workspace_one)
    postmortem = Postmortem.create!(incident: incident, generated_by: member, title: "Pool",
                                    status: Postmortem::STATUS_DRAFT, content: { "html" => "<p>It was the pool</p>" })

    assert_no_enqueued_jobs(only: IncidentLearningJob) { postmortem.update_status!(Postmortem::STATUS_IN_REVIEW, by: member) }
    assert_enqueued_with(job: IncidentLearningJob, args: [ incident.id, true ]) { postmortem.update_status!(Postmortem::STATUS_COMPLETED, by: member) }
    assert_no_enqueued_jobs(only: IncidentLearningJob) { postmortem.update_status!(Postmortem::STATUS_COMPLETED, by: member) }
  end

  test "whoever last marked it completed is read from its history, not whoever wrote the draft" do
    incident = incidents(:active_critical_ws1)
    postmortem = Postmortem.create!(incident: incident, generated_by: workspace_memberships(:alice_workspace_one), title: "Pool",
                                    status: Postmortem::STATUS_DRAFT, content: { "html" => "<p>It was the pool</p>" })
    assert_nil postmortem.completed_by

    postmortem.update_status!(Postmortem::STATUS_COMPLETED, by: workspace_memberships(:bob_workspace_one))
    postmortem.update_content!("<p>It was the pool, sized 20</p>", by: workspace_memberships(:alice_workspace_one))

    assert_equal workspace_memberships(:bob_workspace_one), postmortem.completed_by
  end

  test "of two people completing it at once, only the one who completed it first is on record and the job is queued once" do
    incident = incidents(:active_critical_ws1)
    postmortem = Postmortem.create!(incident: incident, generated_by: workspace_memberships(:alice_workspace_one), title: "Pool",
                                    status: Postmortem::STATUS_IN_REVIEW, content: { "html" => "<p>It was the pool</p>" })
    stale = Postmortem.find(postmortem.id)

    assert_enqueued_jobs(1, only: IncidentLearningJob) do
      postmortem.update_status!(Postmortem::STATUS_COMPLETED, by: workspace_memberships(:bob_workspace_one))
      assert_no_difference -> { postmortem.postmortem_updates.count } do
        stale.update_status!(Postmortem::STATUS_COMPLETED, by: workspace_memberships(:alice_workspace_one))
      end
    end

    assert_equal workspace_memberships(:bob_workspace_one), postmortem.completed_by
    assert_equal Postmortem::STATUS_COMPLETED, stale.status
  end
end

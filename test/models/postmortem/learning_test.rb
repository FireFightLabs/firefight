require "test_helper"

class Postmortem::LearningTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "a postmortem marked completed is read against what the incident taught, and other changes are not" do
    incident = incidents(:active_critical_ws1)
    postmortem = Postmortem.create!(incident: incident, generated_by: workspace_memberships(:alice_workspace_one), title: "Pool",
                                    status: Postmortem::STATUS_DRAFT, content: { "html" => "<p>It was the pool</p>" })

    assert_no_enqueued_jobs(only: IncidentLearningJob) { postmortem.update!(status: Postmortem::STATUS_IN_REVIEW) }
    assert_enqueued_with(job: IncidentLearningJob, args: [ incident.id, true ]) { postmortem.update!(status: Postmortem::STATUS_COMPLETED) }
  end
end

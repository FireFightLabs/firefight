require "test_helper"

class Onboarding::EventSubscriberTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @first = incidents(:active_critical_ws1)
    @onboarding = @workspace.create_onboarding!(installer: workspace_memberships(:alice_workspace_one))
  end

  test "a progress event on the first incident refreshes the checklist" do
    assert_enqueued_with(job: WorkspaceOnboardingProgressJob, args: [ @onboarding.id ]) do
      Onboarding::EventSubscriber.handle(event(IncidentEvent::LEAD_ASSIGNED, @first))
    end
  end

  test "other incidents and other events are ignored" do
    assert_no_enqueued_jobs do
      Onboarding::EventSubscriber.handle(event(IncidentEvent::LEAD_ASSIGNED, incidents(:active_major_ws1)))
      Onboarding::EventSubscriber.handle(event(IncidentEvent::ACTION_CREATED, @first))
    end
  end

  test "a workspace without an onboarding row is ignored" do
    @onboarding.destroy!

    assert_no_enqueued_jobs do
      Onboarding::EventSubscriber.handle(event(IncidentEvent::INCIDENT_CREATED, @first))
    end
  end

  private

  def event(type, incident)
    DomainEvent.new(event_type: type, incident_id: incident.id, data: {}, occurred_at: Time.current)
  end
end

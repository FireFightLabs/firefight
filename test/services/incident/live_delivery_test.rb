require "test_helper"

class Incident::LiveDeliveryTest < ActiveSupport::TestCase
  include ActionCable::TestHelper
  include ActiveJob::TestHelper

  PART = Incident::LiveSignal::PART_INCIDENT

  setup do
    # The test environment caches nothing, and the window lives in the cache.
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    @incident = incidents(:active_critical_ws1)
    @stream = IncidentChannel.stream_name(@incident.id)
  end

  test "a storm of changes to one part is said once at once and once after the window, never once per change" do
    assert_enqueued_jobs 1, only: IncidentPageSignalJob do
      50.times { Incident::LiveDelivery.changed(incident_id: @incident.id, part: PART) }
    end
    assert_broadcasts @stream, 1

    travel Incident::LiveDelivery::WINDOW * 2 do
      perform_enqueued_jobs(only: IncidentPageSignalJob)
    end

    assert_broadcasts @stream, 2
  end

  test "a trailing say that finds the window taken again waits for the next one instead of saying twice in a window" do
    Incident::LiveDelivery.changed(incident_id: @incident.id, part: PART)
    Incident::LiveDelivery.changed(incident_id: @incident.id, part: PART)
    # The booking is run by hand below, at the time it matters.
    clear_enqueued_jobs

    travel Incident::LiveDelivery::WINDOW * 2 do
      Incident::LiveDelivery.changed(incident_id: @incident.id, part: PART)
      assert_broadcasts @stream, 2

      assert_enqueued_jobs 1, only: IncidentPageSignalJob do
        IncidentPageSignalJob.perform_now(@incident.id, PART)
      end
      assert_broadcasts @stream, 2
    end

    travel Incident::LiveDelivery::WINDOW * 4 do
      IncidentPageSignalJob.perform_now(@incident.id, PART)
      assert_broadcasts @stream, 3
    end
  end

  test "a change held back is said by the trailing job even after the window has passed" do
    Incident::LiveDelivery.changed(incident_id: @incident.id, part: PART)
    Incident::LiveDelivery.changed(incident_id: @incident.id, part: PART)

    travel Incident::LiveDelivery::WINDOW * 2 do
      perform_enqueued_jobs(only: IncidentPageSignalJob)
      assert_broadcasts @stream, 2

      # The trailing say took this window, so a change now waits for the next one.
      assert_enqueued_jobs 1, only: IncidentPageSignalJob do
        Incident::LiveDelivery.changed(incident_id: @incident.id, part: PART)
      end
      assert_broadcasts @stream, 2
    end
  end

  test "each part and each incident has its own window" do
    other = incidents(:active_major_ws1)

    Incident::LiveDelivery.changed(incident_id: @incident.id, part: PART)
    Incident::LiveDelivery.changed(incident_id: @incident.id, part: Incident::LiveSignal::PART_TIMELINE)
    Incident::LiveDelivery.changed(incident_id: other.id, part: PART)

    assert_broadcasts @stream, 2
    assert_broadcasts IncidentChannel.stream_name(other.id), 1
    assert_no_enqueued_jobs only: IncidentPageSignalJob
  end

  test "a model's change reaches the delivery through its notification, never by naming the channel" do
    Incident::LiveDelivery.expects(:changed).with(incident_id: @incident.id, part: PART)

    @incident.update!(summary: "Checkout recovered")
  end
end

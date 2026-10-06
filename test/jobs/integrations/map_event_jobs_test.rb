require "test_helper"

module Integrations
  class MapEventJobsTest < ActiveJob::TestCase
    include LiveUpdatesTestHelper

    setup do
      @workspace = workspaces(:slack_workspace_one)
    end

    test "events older than a week are dropped and newer ones kept" do
      row = connect_live!(@workspace)
      MapEvents.receive!(row, [ event("old", at: 8.days.ago) ], received_at: 8.days.ago)
      MapEvents.receive!(row, [ event("new", at: 1.day.ago) ], received_at: 1.day.ago)

      MapEventCleanupJob.perform_now

      assert_equal [ "new" ], ResourceMap::ReceivedEvent.where(integration_environment: row).pluck(:provider_event_id)
    end

    test "the schedule queues a read of each connection whose provider keeps a change log when it is due, and none for others" do
      polled = connect_live!(@workspace, provider: "livepoll", name: "Live poll")
      connect_live!(@workspace)

      assert_enqueued_with(job: MapEventPollJob, args: [ polled ]) { MapEventPollJob.perform_now }
      assert_enqueued_jobs 1, only: MapEventPollJob

      polled.update!(map_events_polled_at: 1.minute.ago)
      assert_no_enqueued_jobs(only: MapEventPollJob) { MapEventPollJob.perform_now }
    end

    test "every job is on the schedule" do
      schedule = YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true)
      %w[production staging development].each do |environment|
        classes = schedule.fetch(environment).values.map { |entry| entry["class"] }
        %w[Integrations::MapEventPollJob Integrations::MapEventWebhookRefreshJob Integrations::MapEventCleanupJob].each do |job|
          assert_includes classes, job, "#{job} runs in #{environment}"
        end
      end
    end
  end
end

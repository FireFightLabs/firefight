require "test_helper"

module Integrations
  class MapEventsTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper
    include LiveUpdatesTestHelper

    setup do
      LiveTestPack.reset!
      @workspace = workspaces(:slack_workspace_one)
      @row = connect_live!(@workspace)
      @web = LiveTestPack.found(ResourceMap::KIND_SERVICE, "web")
      @worker = LiveTestPack.found(ResourceMap::KIND_SERVICE, "worker")
      LiveTestPack.world = { [ @web.kind, "web" ] => @web, [ @worker.kind, "worker" ] => @worker }
      MapSweep.run!(@row)
    end

    def resource(name) = ResourceMap::Resource.find_by!(workspace: @workspace, provider: "livetest", external_id: name)

    def scope_key(name = "web", kind: ResourceMap::KIND_SERVICE) = ResourceMap::Scope.new(account: LiveTestPack::ACCOUNT, kind: kind, external_id: name).key

    test "a source's deliveries are verified and read as events through its definition" do
      body, headers = live_delivery([ change("e1", at: 1.minute.ago) ], secret: "whsec")
      source = MapEvents.source_of("livetest")

      assert source.verify(raw_body: body, headers: headers, secret: "whsec")
      assert_not source.verify(raw_body: body, headers: headers, secret: "another")
      events = source.events(JSON.parse(body), headers: headers)
      assert_equal [ "e1" ], events.map(&:id)
      assert_equal ResourceMap::Scope.new(account: "acme", kind: ResourceMap::KIND_SERVICE, external_id: "web"), events.first.scope
      assert_nil MapEvents.source_of("notion")
    end

    test "the same event delivered twice is kept and read again once" do
      at = 1.minute.ago

      assert_enqueued_jobs 1, only: MapEventJob do
        assert_equal 1, MapEvents.receive!(@row, [ event("e1", at: at) ])
        assert_equal 0, MapEvents.receive!(@row, [ event("e1", at: at) ])
      end
      assert_equal 1, ResourceMap::ReceivedEvent.where(integration_environment: @row).count
      assert_not_nil @row.reload.map_events_received_at
    end

    test "a burst of events about one scope is one re-read, and the job queued for each later one finds nothing left" do
      MapEvents.receive!(@row, [ event("e1", at: 3.minutes.ago), event("e2", at: 2.minutes.ago) ])
      MapEvents.receive!(@row, [ event("e3", at: 1.minute.ago) ])
      LiveTestPack.world[[ @web.kind, "web" ]] = @web.with(status: "failed")

      perform_enqueued_jobs(only: MapEventJob)

      assert_equal 1, LiveTestPack.reads.size
      assert_equal "failed", resource("web").status
      assert_equal [ ResourceMap::ReceivedEvent::OUTCOME_APPLIED ], ResourceMap::ReceivedEvent.where(integration_environment: @row).distinct.pluck(:outcome)
      assert_equal 1.minute.ago.to_i, resource("web").changes_seen.find_by!(kind: ResourceMap::Change::KIND_STATUS_CHANGED).happened_at.to_i, "the change is at the latest event's time"
    end

    test "events out of order reach the same map, since each re-read reads what the provider has now" do
      LiveTestPack.world[[ @web.kind, "web" ]] = @web.with(status: "failed")
      MapEvents.receive!(@row, [ event("late", at: 1.minute.ago) ])
      perform_enqueued_jobs(only: MapEventJob)
      MapEvents.receive!(@row, [ event("early", at: 5.minutes.ago) ])
      perform_enqueued_jobs(only: MapEventJob)

      assert_equal "failed", resource("web").status
      assert_equal 1, resource("web").changes_seen.where(kind: ResourceMap::Change::KIND_STATUS_CHANGED).count
    end

    test "an event saying something was removed removes nothing until the re-read finds it gone" do
      MapEvents.receive!(@row, [ event("e1", at: 1.minute.ago, name: "worker", action: ResourceMap::Event::REMOVED) ])
      perform_enqueued_jobs(only: MapEventJob)
      assert_nil resource("worker").removed_at, "the provider still has it"

      LiveTestPack.world.delete([ @worker.kind, "worker" ])
      MapEvents.receive!(@row, [ event("e2", at: 30.seconds.ago, name: "worker", action: ResourceMap::Event::REMOVED) ])
      perform_enqueued_jobs(only: MapEventJob)

      assert_not_nil resource("worker").removed_at
    end

    test "a scope the provider cannot read on its own sweeps the connection once, however many events ask" do
      LiveTestPack.narrows = false
      MapEvents.receive!(@row, [ event("e1", at: 1.minute.ago), event("e2", at: 1.minute.ago, name: "worker") ])

      perform_enqueued_jobs(only: MapEventJob)
      assert_enqueued_jobs 2, only: MapEventSweepJob
      MapSweep.expects(:run!).once.with { |row| row.update!(map_swept_at: Time.current) }
      perform_enqueued_jobs(only: MapEventSweepJob)

      assert_equal [ ResourceMap::ReceivedEvent::OUTCOME_SWEPT ], ResourceMap::ReceivedEvent.where(integration_environment: @row).distinct.pluck(:outcome)
    end

    test "a change to what the connection reaches sweeps it in full" do
      MapEvents.receive!(@row, [ ResourceMap::Event.new(id: "r1", at: 1.minute.ago, action: ResourceMap::Event::RESCOPE) ])

      assert_enqueued_jobs 1, only: MapEventSweepJob do
        perform_enqueued_jobs(only: MapEventJob)
      end
      assert_empty LiveTestPack.reads
    end

    test "a provider asking Firefight to slow down leaves the change to the next sweep and says so" do
      LiveTestPack.refusal = Integrations::Error.new("Live test answered 429: slow down").extend(RateLimited)
      MapEvents.receive!(@row, [ event("e1", at: 1.minute.ago) ])
      perform_enqueued_jobs(only: MapEventJob)

      assert_equal ResourceMap::ReceivedEvent::OUTCOME_DEFERRED, ResourceMap::ReceivedEvent.find_by!(provider_event_id: "e1").outcome
      assert_includes @row.reload.map_gaps, "Live test asked Firefight to slow down, so a change it reported is read at the next sweep."
    end

    test "the hourly sweep still takes away what a missed event would have" do
      LiveTestPack.world.delete([ @worker.kind, "worker" ])

      MapSweep.run!(@row)

      assert_not_nil resource("worker").removed_at
    end

    test "polling reads the change log after its cursor and keeps the new one" do
      row = connect_live!(@workspace, provider: "livepoll", name: "Live poll")
      LiveTestPoll.log = [ [ "c1", event("p1", at: 2.minutes.ago) ], [ "c2", event("p2", at: 1.minute.ago) ] ]

      MapEvents.poll!(row)
      assert_equal "c2", row.reload.map_events_cursor
      assert_equal %w[p1 p2], ResourceMap::ReceivedEvent.where(integration_environment: row).order(:provider_event_id).pluck(:provider_event_id)

      LiveTestPoll.log << [ "c3", event("p3", at: 30.seconds.ago) ]
      MapEvents.poll!(row)
      assert_equal "c3", row.reload.map_events_cursor
      assert_equal 3, ResourceMap::ReceivedEvent.where(integration_environment: row).count
    ensure
      LiveTestPoll.log = []
    end

    test "a change log the provider refuses for what the connection may read is read again a day later, or at once on a connection change" do
      row = connect_live!(@workspace, provider: "livepoll", name: "Live poll")
      LiveTestPoll.refusal = "Live poll refused the audit log: forbidden."

      MapEvents.poll!(row)
      row.reload
      assert_equal [ "Live poll refused the audit log: forbidden.", false ], [ row.map_events_error, row.live_updates.on ]
      assert_match "Firefight tries again tomorrow.", row.live_updates.reason
      assert_not row.map_events_poll_due?
      assert row.map_events_poll_due?(at: 1.day.from_now)

      MapEvents.prepare!(row, now: true)
      assert row.reload.map_events_poll_due?
      LiveTestPoll.refusal = nil
      MapEvents.poll!(row)
      assert_equal [ nil, nil, true ], [ row.reload.map_events_error, row.map_events_refused_at, row.live_updates.on ]
    ensure
      LiveTestPoll.refusal = nil
      LiveTestPoll.log = []
    end

    test "a change log is read as often as its provider says" do
      row = connect_live!(@workspace, provider: "livepoll", name: "Live poll")
      assert row.map_events_poll_due?

      MapEvents.poll!(row)
      assert_not row.reload.map_events_poll_due?
      assert_not row.map_events_poll_due?(at: 4.minutes.from_now)
      assert row.map_events_poll_due?(at: 5.minutes.from_now - 20.seconds), "a read due within the minute goes now"
      assert_not @row.map_events_poll_due?, "a provider that keeps no change log is never read"
    ensure
      LiveTestPoll.log = []
    end

    test "an event read both by polling and by a delivery is read again once" do
      row = connect_live!(@workspace, provider: "livepoll", name: "Live poll")
      LiveTestPoll.log = [ [ "c1", event("same", at: 1.minute.ago) ] ]

      assert_enqueued_jobs 1, only: MapEventJob do
        MapEvents.receive!(row, [ event("same", at: 1.minute.ago) ])
        MapEvents.poll!(row)
      end
    ensure
      LiveTestPoll.log = []
    end

    test "Firefight registers the provider's webhook where it can, gives each row its own address, and takes the webhook back" do
      row = connect_live!(@workspace, provider: "livehook", name: "Live hook")

      with_app_host { MapEvents.prepare!(row) }
      row.reload

      assert row.map_events_token.present?
      assert_equal "hook-1", row.map_events_webhook_id
      assert_equal "registered-secret", row.map_events_secret
      assert_equal "https://firefight.example.com/api/v1/map_events/#{row.map_events_token}", LiveTestHook.registered
      assert row.live_updates.on

      MapEvents.connection_removed(row.integration)
      assert_equal "hook-1", LiveTestHook.removed
      assert_nil row.reload.map_events_webhook_id
    end

    test "a registration that fails is the connection's reason, and lapsing webhooks are extended" do
      row = connect_live!(@workspace, provider: "livehook", name: "Live hook")
      LiveTestHook.failure = "Live hook answered 403: not allowed"

      with_app_host { MapEvents.prepare!(row) }
      state = row.reload.live_updates
      assert_not state.on
      assert_equal "Firefight could not follow Live hook's changes: Live hook answered 403: not allowed. The map still updates at each sweep.", state.reason

      LiveTestHook.failure = nil
      with_app_host { MapEvents.prepare!(row) }
      MapEventWebhookRefreshJob.perform_now
      assert_operator row.reload.map_events_expires_at, :>, 20.days.from_now
      assert_nil row.map_events_error
    ensure
      LiveTestHook.failure = nil
    end

    test "each registration, extension and removal is in the activity log under the map sweep, a refusal with the provider's words" do
      row = connect_live!(@workspace, provider: "livehook", name: "Live hook")
      LiveTestHook.failure = "Live hook answered 403: not allowed"
      with_app_host { MapEvents.prepare!(row) }
      LiveTestHook.failure = nil
      with_app_host { MapEvents.prepare!(row) }
      MapEventWebhookRefreshJob.perform_now
      MapEvents.connection_removed(row.integration)

      logged = Ability::Invocation.where(workspace: @workspace, source: AbilityGateway::SOURCE_MAP_SWEEP).order(:created_at)
      assert_equal [ [ "register", Ability::Invocation::OUTCOME_ERROR, "Live hook answered 403: not allowed" ],
                     [ "register", Ability::Invocation::OUTCOME_SUCCESS, nil ], [ "refresh", Ability::Invocation::OUTCOME_SUCCESS, nil ],
                     [ "remove", Ability::Invocation::OUTCOME_SUCCESS, nil ] ],
                   logged.map { |invocation| [ invocation.params["webhook"], invocation.outcome, invocation.error_summary ] }
      assert logged.all? { |invocation| invocation.principal_label == SystemAgent.map_sweep.principal_label && invocation.params["connection"] == "livehook" }
      assert logged.all? { |invocation| invocation.action_key == IntegrationEnvironment::MAP_EVENTS_WEBHOOK_ACTION_KEY && invocation.triggered_by_label == "Live updates" }
    ensure
      LiveTestHook.failure = nil
    end

    test "a registration refused for the plan or a limit is tried again a day later, and at once on a connection change" do
      row = connect_live!(@workspace, provider: "livehook", name: "Live hook")
      LiveTestHook.refusal = "Live hook answered 403: not on this plan"
      with_app_host { MapEvents.prepare!(row) }
      assert_equal "Firefight could not follow Live hook's changes: Live hook answered 403: not on this plan. Firefight tries again tomorrow. " \
                   "The map still updates at each sweep.", row.reload.live_updates.reason

      LiveTestHook.refusal = nil
      travel 23.hours do
        with_app_host { MapEvents.prepare!(row) }
        assert_nil row.reload.map_events_webhook_id, "an hourly sweep within the day does not try again"
        with_app_host { MapEvents.prepare!(row, now: true) }
        assert_equal "hook-1", row.reload.map_events_webhook_id, "a connection change tries at once"
      end
      assert_equal 2, Ability::Invocation.where(workspace: @workspace, source: AbilityGateway::SOURCE_MAP_SWEEP).count

      row.update!(map_events_webhook_id: nil, map_events_refused_at: 25.hours.ago)
      with_app_host { MapEvents.prepare!(row) }
      assert_equal "hook-1", row.reload.map_events_webhook_id, "a day later the sweep tries again"
    ensure
      LiveTestHook.refusal = nil
    end

    test "a source that asks first waits for a person, who turns live updates on and off" do
      row = connect_live!(@workspace, provider: "livehook", name: "Live hook")
      LiveTestHook.asking = "Firefight's would be the account's only webhook."
      LiveTestHook.registered = nil

      with_app_host { MapEvents.prepare!(row) }
      row.reload
      assert_nil LiveTestHook.registered
      assert_not row.live_updates.on
      assert_equal "Firefight asks before adding its webhook to Live hook. Firefight's would be the account's only webhook.", row.live_updates.reason
      assert_equal LiveTestHook.asking, row.live_updates_turn_on_words
      assert_nil row.live_updates_turn_on_blocked_reason
      with_app_host { MapEvents.prepare!(row) }
      assert_nil LiveTestHook.registered, "the hourly sweep does not decide for the person"

      with_app_host { MapEvents.turn_on!(row) }
      assert row.reload.live_updates.on
      assert_equal "Live updates are already on for Live hook.", row.live_updates_turn_on_blocked_reason
      assert_nil row.live_updates_turn_off_blocked_reason

      MapEvents.turn_off!(row)
      row.reload
      assert_equal [ "hook-1", nil ], [ LiveTestHook.removed, row.map_events_webhook_id ]
      assert_equal "Live updates were turned off, so the map updates at each sweep.", row.live_updates.reason
      LiveTestHook.asking = nil
      with_app_host { MapEvents.prepare!(row, now: true) }
      assert_nil row.reload.map_events_webhook_id, "nothing registers again until a person turns them on"
      assert_equal %w[register remove], Ability::Invocation.where(workspace: @workspace, source: AbilityGateway::SOURCE_MAP_SWEEP).order(:created_at).map { |each| each.params["webhook"] }
    ensure
      LiveTestHook.asking = nil
    end

    test "a connection whose webhook costs nothing cannot be turned off" do
      row = connect_live!(@workspace, provider: "livehook", name: "Live hook")
      with_app_host { MapEvents.prepare!(row) }

      assert_equal "Firefight's webhook costs Live hook nothing, so live updates stay on while it is connected.", row.reload.live_updates_turn_off_blocked_reason
    end

    test "a provider that asks Firefight to slow down while it registers is tried again at the next sweep" do
      row = connect_live!(@workspace, provider: "livehook", name: "Live hook")
      LiveTestHook.stubs(:register).raises(Integrations::Error.new("Live hook answered 429: slow down").extend(Integrations::RateLimited))

      with_app_host { MapEvents.prepare!(row) }

      assert_equal "Firefight could not follow Live hook's changes: Live hook asked it to slow down, so Firefight registers again at the next sweep. " \
                   "The map still updates at each sweep.", row.reload.live_updates.reason
    end

    test "a connection set up by hand is off until its signing secret is saved" do
      state = @row.live_updates

      assert_not state.on
      assert_equal "Send Live test's changes to Firefight and save the signing secret under Integrations to turn them on.", state.reason
      assert @row.map_events_set_up_by_hand?

      @row.save_map_events_secret!("  whsec  ")
      assert @row.reload.live_updates.on
      assert_equal "whsec", @row.map_events_secret
    end

    test "a provider that cannot say what changed has no live updates" do
      row = connection("northflank", Integration::KIND_NATIVE)

      assert_nil row.live_updates
    end

    test "app wide deliveries reach the connections made through the installation they name" do
      row = connect_live!(@workspace, provider: "liveapp", name: "Live app")
      row.store_installation!("42")
      connect_live!(workspaces(:slack_workspace_two), provider: "liveapp", name: "Live app").store_installation!("7")

      assert_equal [ row.id ], MapEvents.rows_for_installation("liveapp", 42).pluck(:id)
      assert_empty MapEvents.rows_for_installation("liveapp", nil)
    end

    private

    def connection(provider, kind)
      integration = @workspace.integrations.create!(kind: kind, provider: provider, name: provider.capitalize, slug: provider)
      integration.integration_environments.create!
    end
  end
end

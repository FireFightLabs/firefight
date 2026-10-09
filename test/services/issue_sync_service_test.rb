require "test_helper"

class IssueSyncServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include IssueTrackerTestHelper

  URL = "https://linear.app/acme/issue/ENG-12/rotate".freeze
  ISSUE = { "id" => "ENG-12", "title" => "Rotate the database password", "url" => URL, "statusType" => "backlog" }.freeze
  STATUSES = [ { "id" => "s-todo", "type" => "unstarted" }, { "id" => "s-doing", "type" => "started" },
               { "id" => "s-done", "type" => "completed" } ].freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @incident = Incident.create!(
      workspace: @workspace, declared_by: @alice, incident_status: incident_statuses(:investigating_ws1),
      incident_severity: incident_severities(:critical_ws1), name: "Database down", is_private: false,
      channel_id: "C_ISSUES", source: Incident::SOURCE_SLACK
    )
    @linear = connect_tracker!(@workspace, provider: "linear")
    @items = IncidentActionService.new(@workspace)
    @service = IssueSyncService.new(@workspace)
    stub_post_message
    stub_update_message
    stub_get_permalink
    tracker_answers(
      "save_issue" => json_answer(ISSUE), "list_users" => json_answer([ { "id" => "u-alice", "email" => "alice@example.com" } ]),
      "list_issue_statuses" => json_answer(STATUSES), "get_issue" => json_answer(ISSUE)
    )
  end

  def create_item(type = IncidentAction::ACTION_TYPE_FOLLOWUP, assignee: nil, by: @alice)
    perform_enqueued_jobs do
      @items.create_action(incident: @incident, created_by: by, action_type: type, description: "Rotate the database password", assignee: assignee)
    end
  end

  def linked_item(**attributes)
    @incident.incident_actions.create!(created_by: @alice, action_type: IncidentAction::ACTION_TYPE_FOLLOWUP, description: "Rotate the database password",
                                       status: IncidentAction::STATUS_OPEN, external_key: "ENG-12", external_url: URL, issue_integration: @linear,
                                       issue_sync_state: IncidentAction::ISSUE_LINKED, message_ts: "1700000000.000100", **attributes)
  end

  def event(at: Time.current, **fields)
    Integrations::Issues::Event.new(keys: [ "ENG-12" ], at: at, url: URL, **fields)
  end

  def saves = tracker_calls.select { |name, _| name == "save_issue" }.map(&:last)

  test "never opens no issue, and offers none" do
    sync_with!(@workspace, @linear, creation: Workspace::IssueSync::ISSUE_CREATION_NEVER)

    item = create_item

    assert_nil item.reload.external_url
    assert_empty saves
    assert_not item.issue_request_offered?
  end

  test "only when asked opens none on its own, and opens one when asked, as Firefight issue sync naming who asked" do
    sync_with!(@workspace, @linear, creation: Workspace::IssueSync::ISSUE_CREATION_ASKED)
    item = create_item
    assert_empty saves
    assert item.reload.issue_request_offered?

    with_env("APP_HOST" => "ff.example.com") do
      perform_enqueued_jobs { assert_nil @service.request(item, by: @alice) }
    end

    item.reload
    assert_equal [ "ENG-12", URL, IncidentAction::ISSUE_LINKED, @linear.id ], [ item.external_key, item.external_url, item.issue_sync_state, item.issue_integration_id ]
    assert_equal "Rotate the database password", saves.first["title"]
    assert_match @incident.identifier, saves.first["description"]
    assert_match "https://ff.example.com/app/incidents/#{@incident.id}", saves.first["description"]
    log = Ability::Invocation.find_by!(action_key: "linear.save_issue", source: AbilityGateway::SOURCE_ISSUE_SYNC, incident_id: @incident.id)
    assert_equal [ SystemAgent.issue_sync.id, "Alice Smith, on the follow-up on #{@incident.identifier}" ], [ log.principal_id, log.triggered_by_label ]
    assert_equal "This item already has an issue.", @service.request(item, by: @alice)
  end

  test "opening cut off by a stopped worker never opens a second issue, and the item says to look in the tracker" do
    sync_with!(@workspace, @linear, creation: Workspace::IssueSync::ISSUE_CREATION_ASKED)
    item = create_item
    assert_nil @service.request(item, by: @alice)
    job = IssueSyncJob.new(operation: IssueSyncService::OPEN_ISSUE, action: item, by: @alice)
    IncidentAction.any_instance.stubs(:move_issue!).raises(Interrupt)

    assert_raises(Interrupt) { job.perform_now }
    assert_equal 1, saves.size

    IncidentAction.any_instance.unstub(:move_issue!)
    job.perform_now

    item.reload
    assert_equal 1, saves.size
    assert_equal [ IncidentAction::ISSUE_FAILED, "Firefight restarted while opening its issue. Check Linear for it before asking again." ],
                 [ item.issue_sync_state, item.issue_sync_note ]
    assert item.issue_request_offered?
  end

  test "an item still opening long after its job was lost is ended the same way by the recovery sweep" do
    sync_with!(@workspace, @linear, creation: Workspace::IssueSync::ISSUE_CREATION_ASKED)
    item = create_item
    assert_nil @service.request(item, by: @alice)

    travel IssueSyncService::OPENING_LOST_AFTER + 1.minute do
      IssueSyncService.give_up_lost_openings!
      IssueSyncService.give_up_lost_openings!
    end

    assert_equal IncidentAction::ISSUE_FAILED, item.reload.issue_sync_state
    assert_empty saves
  end

  test "a member with no reach into the tracker still gets the item's issue, since sync makes it as its own agent" do
    sync_with!(@workspace, @linear, creation: Workspace::IssueSync::ISSUE_CREATION_ALL)

    item = create_item(by: @bob).reload

    assert_equal [ IncidentAction::ISSUE_LINKED, "ENG-12" ], [ item.issue_sync_state, item.external_key ]
    assert_not Ability::Invocation.exists?(action_key: "linear.save_issue", principal_id: @bob.id)
    assert_match "Bob", Ability::Invocation.find_by!(action_key: "linear.save_issue", principal_id: SystemAgent.issue_sync.id).triggered_by_label
  end

  test "a grant taken back from Firefight issue sync leaves the item saved and says how to put it back" do
    sync_with!(@workspace, @linear, creation: Workspace::IssueSync::ISSUE_CREATION_ASKED)
    item = create_item
    @workspace.ability_grants.where(principal: SystemAgent.issue_sync).joins(:action).where(ability_actions: { key: "linear.save_issue" }).destroy_all

    assert_match "Firefight issue sync no longer holds linear.save_issue", @service.request(item, by: @alice)
    assert_nil item.reload.issue_sync_state
  end

  test "always for follow-ups opens one for a follow-up and not for an action" do
    sync_with!(@workspace, @linear, creation: Workspace::IssueSync::ISSUE_CREATION_FOLLOW_UPS)

    follow_up = create_item(IncidentAction::ACTION_TYPE_FOLLOWUP)
    action = create_item(IncidentAction::ACTION_TYPE_ACTION)

    assert_equal "ENG-12", follow_up.reload.external_key
    assert_nil action.reload.external_key
    assert action.issue_request_offered?
  end

  test "always for actions and follow-ups opens one for each, assigned to the person whose email the tracker has" do
    sync_with!(@workspace, @linear, creation: Workspace::IssueSync::ISSUE_CREATION_ALL)

    create_item(IncidentAction::ACTION_TYPE_ACTION, assignee: @alice)
    create_item(IncidentAction::ACTION_TYPE_FOLLOWUP)

    assert_equal 2, @incident.incident_actions.where(external_key: "ENG-12").count
    assert_equal "u-alice", saves.first["assignee"]
  end

  test "an item another way linked already, such as one Halon opened, gets no second issue" do
    sync_with!(@workspace, @linear, creation: Workspace::IssueSync::ISSUE_CREATION_ALL)

    perform_enqueued_jobs do
      @items.create_action(incident: @incident, created_by: @alice, action_type: IncidentAction::ACTION_TYPE_FOLLOWUP, description: "x",
                           external_key: "ENG-9", external_url: URL, issue_integration: @linear)
    end

    assert_empty saves
  end

  test "an issue the tracker refuses leaves the item saved, says why and can be tried again" do
    sync_with!(@workspace, @linear, creation: Workspace::IssueSync::ISSUE_CREATION_ALL)
    tracker_answers("save_issue" => error_answer("Team ENG not found"))

    item = create_item.reload

    assert_equal IncidentAction::ISSUE_FAILED, item.issue_sync_state
    assert_equal "Linear refused to open the issue: Team ENG not found.", item.issue_sync_note
    assert item.issue_missing?
    assert item.issue_request_offered?

    tracker_answers("save_issue" => json_answer(ISSUE))
    perform_enqueued_jobs { assert_nil @service.request(item, by: @alice) }
    assert_equal [ IncidentAction::ISSUE_LINKED, nil ], [ item.reload.issue_sync_state, item.issue_sync_note ]
  end

  test "an issue that needs approval waits for it, opens once approved and says so when declined" do
    sync_with!(@workspace, @linear, creation: Workspace::IssueSync::ISSUE_CREATION_ALL)
    AbilityGateway.stubs(:approval_requirement).returns({ "role" => "admin" })

    item = create_item.reload
    assert_equal IncidentAction::ISSUE_AWAITING_APPROVAL, item.issue_sync_state
    assert_match "waiting for approval", item.issue_sync_note
    approval = Ability::Approval.find(item.issue_approval_id)
    assert_equal ApprovalResumption::KIND_ISSUE_SYNC, approval.resume_payload["kind"]

    approval.update!(status: Ability::Approval::STATUS_APPROVED, approver: @alice, resolved_at: Time.current)
    perform_enqueued_jobs { ApprovalResumption.resume!(approval) }
    assert_equal [ IncidentAction::ISSUE_LINKED, "ENG-12" ], [ item.reload.issue_sync_state, item.external_key ]

    declined = create_item.reload
    denial = Ability::Approval.find(declined.issue_approval_id)
    denial.update!(status: Ability::Approval::STATUS_DENIED, approver: @alice, resolved_at: Time.current)
    ApprovalResumption.decline!(denial)
    assert_equal IncidentAction::ISSUE_DECLINED, declined.reload.issue_sync_state
    assert_match "declined opening its issue", declined.issue_sync_note
  end

  test "a removed connection or a create tool switched off is the reason, and the item still saves" do
    sync_with!(@workspace, @linear, creation: Workspace::IssueSync::ISSUE_CREATION_ALL)
    @linear.tools.find_by!(name: "save_issue").update!(enabled: false)

    item = create_item.reload
    assert_equal IncidentAction::ISSUE_FAILED, item.issue_sync_state
    assert_match "Linear's save_issue is switched off", item.issue_sync_note

    @linear.update!(deleted_at: Time.current)
    assert_match "was removed", @workspace.reload.issue_creation_blocked_reason
    assert_match "was removed", @service.request(item.reload, by: @alice)
  end

  test "picking up, handing over and finishing a linked item move its issue, made as Firefight issue sync" do
    sync_with!(@workspace, @linear)
    item = linked_item

    perform_enqueued_jobs { @items.pick_up_action(action: item, picked_up_by: @alice) }
    assert_equal({ "id" => "ENG-12", "assignee" => "u-alice", "state" => "s-doing" }, saves.last)

    perform_enqueued_jobs { @items.complete_action(action: item.reload, completed_by: @bob) }
    assert_equal({ "id" => "ENG-12", "state" => "s-done" }, saves.last)
    labels = Ability::Invocation.where(action_key: "linear.save_issue", principal_id: SystemAgent.issue_sync.id).pluck(:triggered_by_label)
    assert_includes labels, "Bob Jones, on the follow-up on #{@incident.identifier}"
    assert_not Ability::Invocation.exists?(action_key: "linear.save_issue", principal_id: [ @alice.id, @bob.id ])
  end

  test "renaming, reopening and unassigning an item reach its issue, and none of them is sent back again" do
    sync_with!(@workspace, @linear)
    item = linked_item(assignee: @alice, status: IncidentAction::STATUS_DONE)

    perform_enqueued_jobs { assert_nil @items.rename_action(action: item, description: "Rotate every password", renamed_by: @bob) }
    assert_equal({ "id" => "ENG-12", "title" => "Rotate every password" }, saves.last)

    perform_enqueued_jobs { assert_nil @items.reopen_action(action: item.reload, reopened_by: @bob) }
    assert_equal IncidentAction::STATUS_IN_PROGRESS, item.reload.status
    assert_equal({ "id" => "ENG-12", "state" => "s-doing" }, saves.last)

    perform_enqueued_jobs { assert_nil @items.unassign_action(action: item.reload, unassigned_by: @bob) }
    assert_equal [ IncidentAction::STATUS_OPEN, nil ], [ item.reload.status, item.assignee ]
    assert_equal({ "id" => "ENG-12", "assignee" => nil, "state" => "s-todo" }, saves.last)

    assert_equal [ IncidentEvent::ACTION_RENAMED, IncidentEvent::ACTION_REOPENED, IncidentEvent::ACTION_UNASSIGNED ],
                 @incident.incident_events.where(actor: @bob).order(:created_at).pluck(:event_type)
    assert_no_difference -> { saves.size } do
      perform_enqueued_jobs { @service.apply(event(at: 1.second.from_now, state: Integrations::Issues::STATE_OPEN, changed: [ Integrations::Issues::FIELD_STATE ])) }
    end
  end

  test "a person the tracker has no account for leaves its assignee alone, and the item says so" do
    sync_with!(@workspace, @linear)
    item = linked_item

    perform_enqueued_jobs { @items.reassign_action(action: item, assignee: @bob, reassigned_by: @alice) }

    assert_equal({ "id" => "ENG-12", "state" => "s-doing" }, saves.last)
    assert_match "Linear has nobody with the email bob@example.com", item.reload.issue_sync_note
  end

  test "a change the tracker made is applied as Firefight's issue sync, recorded, and never sent back" do
    sync_with!(@workspace, @linear)
    item = linked_item(assignee: @bob, status: IncidentAction::STATUS_IN_PROGRESS)

    perform_enqueued_jobs do
      @service.apply(event(title: "Rotate every password", state: Integrations::Issues::STATE_DONE, assignee_email: "alice@example.com",
                           changed: Integrations::Issues::FIELDS))
    end

    item.reload
    assert_equal [ "Rotate every password", IncidentAction::STATUS_DONE, @alice ], [ item.description, item.status, item.assignee ]
    events = @incident.incident_events.where(actor: SystemAgent.issue_sync).pluck(:event_type)
    assert_equal [ IncidentEvent::ACTION_RENAMED, IncidentEvent::ACTION_COMPLETED, IncidentEvent::ACTION_REASSIGNED ].sort, events.sort
    assert_empty saves
    log = Ability::Invocation.find_by!(principal_id: SystemAgent.issue_sync.id, source: AbilityGateway::SOURCE_ISSUE_SYNC, incident_id: @incident.id)
    assert_equal %w[title status assignee], log.params["changed"]
  end

  test "reopening the issue reopens the item, and unassigning it leaves the item open with nobody" do
    sync_with!(@workspace, @linear)
    item = linked_item(assignee: @bob, status: IncidentAction::STATUS_DONE)

    @service.apply(event(state: Integrations::Issues::STATE_STARTED, changed: [ Integrations::Issues::FIELD_STATE ]))
    assert_equal IncidentAction::STATUS_IN_PROGRESS, item.reload.status

    @service.apply(event(at: 1.second.from_now, assignee_email: nil, changed: [ Integrations::Issues::FIELD_ASSIGNEE ]))
    assert_equal [ IncidentAction::STATUS_OPEN, nil ], [ item.reload.status, item.assignee ]
    assert @incident.incident_events.exists?(event_type: IncidentEvent::ACTION_REOPENED)
    assert @incident.incident_events.exists?(event_type: IncidentEvent::ACTION_UNASSIGNED)
  end

  test "a tracker account matching nobody here leaves the item's assignee alone and says so" do
    sync_with!(@workspace, @linear)
    item = linked_item(assignee: @bob, status: IncidentAction::STATUS_IN_PROGRESS)

    @service.apply(event(assignee_email: "stranger@example.com", assignee_name: "Stranger", changed: [ Integrations::Issues::FIELD_ASSIGNEE ]))

    assert_equal @bob, item.reload.assignee
    assert_match "Stranger has no Firefight account with the email stranger@example.com", item.issue_sync_note
  end

  test "a change made here after the tracker's wins over it, whichever arrives last, so nothing flip-flops" do
    sync_with!(@workspace, @linear)
    item = linked_item
    reported_at = Time.current

    perform_enqueued_jobs { @items.complete_action(action: item, completed_by: @alice) }
    @service.apply(event(at: reported_at, state: Integrations::Issues::STATE_OPEN, changed: [ Integrations::Issues::FIELD_STATE ]))

    assert_equal IncidentAction::STATUS_DONE, item.reload.status
    assert_not @incident.incident_events.exists?(event_type: IncidentEvent::ACTION_REOPENED)
  end

  test "the tracker's echo of a change made here changes nothing, and deliveries out of order keep the newest" do
    sync_with!(@workspace, @linear)
    item = linked_item

    perform_enqueued_jobs { @items.complete_action(action: item, completed_by: @alice) }
    assert_no_difference -> { @incident.incident_events.count } do
      @service.apply(event(at: 1.second.from_now, state: Integrations::Issues::STATE_DONE, changed: [ Integrations::Issues::FIELD_STATE ]))
    end

    @service.apply(event(at: 10.seconds.from_now, title: "Newest", changed: [ Integrations::Issues::FIELD_TITLE ]))
    @service.apply(event(at: 5.seconds.from_now, title: "Older", changed: [ Integrations::Issues::FIELD_TITLE ]))
    assert_equal "Newest", item.reload.description
  end

  test "two deliveries of the same change racing apply it once" do
    sync_with!(@workspace, @linear)
    item = linked_item
    closing = event(state: Integrations::Issues::STATE_DONE, changed: [ Integrations::Issues::FIELD_STATE ])
    stale = IncidentAction.find(item.id)

    @service.apply(closing)
    applied = IncidentActionService.new(@workspace).apply_issue_change(
      action: stale, field: Integrations::Issues::FIELD_STATE, at: closing.at, by: SystemAgent.issue_sync, from_status: IncidentAction::STATUS_OPEN,
      event_type: IncidentEvent::ACTION_COMPLETED, status: IncidentAction::STATUS_DONE
    )

    assert_not applied
    assert_equal 1, @incident.incident_events.where(event_type: IncidentEvent::ACTION_COMPLETED).count
  end

  test "a deleted or archived issue stops the item being kept in step, and a moved one is found by its old key" do
    sync_with!(@workspace, @linear)
    item = linked_item

    @service.apply(Integrations::Issues::Event.new(keys: [ "OPS-1", "ENG-12" ], at: Time.current, url: "https://linear.app/acme/issue/OPS-1/rotate",
                                                   title: "Moved", changed: [ Integrations::Issues::FIELD_TITLE ]))
    assert_equal [ "OPS-1", "Moved" ], [ item.reload.external_key, item.description ]

    @service.apply(Integrations::Issues::Event.new(keys: [ "OPS-1" ], at: Time.current, gone: Integrations::Issues::GONE_DELETED))
    item.reload
    assert_equal IncidentAction::ISSUE_GONE, item.issue_sync_state
    assert_match "OPS-1 was deleted in Linear", item.issue_sync_note
    assert_not item.issue_syncs?

    perform_enqueued_jobs { @items.complete_action(action: item, completed_by: @alice) }
    assert_empty saves
  end

  test "an issue deleted in the tracker found by a change made here stops the item being kept in step" do
    sync_with!(@workspace, @linear)
    item = linked_item
    tracker_answers("list_users" => json_answer([]), "list_issue_statuses" => json_answer(STATUSES),
                    "save_issue" => error_answer("Entity not found: Issue"), "get_issue" => error_answer("Entity not found: Issue"))

    perform_enqueued_jobs { @items.complete_action(action: item, completed_by: @alice) }

    assert_equal IncidentAction::ISSUE_GONE, item.reload.issue_sync_state
  end

  test "items on a connection that is no longer the workspace's tracker are not kept in step" do
    sync_with!(@workspace, @linear)
    item = linked_item
    jira = connect_tracker!(@workspace, provider: "jira")
    @workspace.update!(issue_tracker: jira.slug, issue_tracker_target: { "site" => "acme.atlassian.net", "project" => "OPS" })

    @service.apply(event(state: Integrations::Issues::STATE_DONE, changed: [ Integrations::Issues::FIELD_STATE ]))
    perform_enqueued_jobs { @items.pick_up_action(action: item.reload, picked_up_by: @alice) }

    assert_equal IncidentAction::STATUS_IN_PROGRESS, item.reload.status
    assert_empty tracker_calls
  end

  private

  def with_env(values)
    previous = values.keys.index_with { |key| ENV[key] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end
end

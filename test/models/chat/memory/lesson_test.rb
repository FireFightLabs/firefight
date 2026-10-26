require "test_helper"

class Chat::Memory::LessonTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @admin = workspace_memberships(:alice_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
  end

  test "only the incident lead or a workspace admin may decide on a lesson, and a memory from elsewhere is no lesson" do
    lesson = taught("A 5xx spike on web after a deploy has meant the migration job failed")

    assert_nil lesson.approve_blocked_reason(@admin)
    assert_equal "Only the INC-001 lead or a workspace admin can decide on its lessons.", lesson.approve_blocked_reason(@member)

    @incident.lead = @member
    assert_nil lesson.reload.approve_blocked_reason(@member)

    chat = Chat::Memory.create!(workspace: @workspace, text: "Deploys happen from main", state: Chat::Memory::STATE_UNCONFIRMED)
    assert_equal "Only lessons an incident taught are approved for pull request reviews.", chat.approve_blocked_reason(@admin)
  end

  test "approving leaves how Halon trusts the memory as it was, may make it strict, and puts it in what reviews check" do
    lesson = taught("Checkout retries go up when the payment timeout changes")

    assert lesson.approve!(by: @admin, strict: true)

    assert_equal [ Chat::Memory::STATE_UNCONFIRMED, nil, @admin, true ], [ lesson.state, lesson.confirmed_by, lesson.approved_by, lesson.strict ]
    assert_equal Chat::Memory::Lesson::STATUS_APPROVED, lesson.lesson_status
    assert_equal [ lesson ], Chat::Memory.for_review(@workspace, [])
    assert_equal "It is approved already.", lesson.approve_blocked_reason(@admin)
    assert_not lesson.approve!(by: @admin)
  end

  test "a member cannot approve, and an approved lesson that is disputed since stops being checked until a person decides" do
    lesson = taught("Checkout keeps sessions in Redis")

    assert_not lesson.approve!(by: @member)
    assert_nil lesson.reload.approved_at

    lesson.approve!(by: @admin)
    lesson.dispute!("The INC-001 postmortem says otherwise")

    assert_equal Chat::Memory::Lesson::STATUS_WAITING, lesson.lesson_status
    assert_empty Chat::Memory.for_review(@workspace, [])
    assert_match "Halon stopped using it", lesson.approve_blocked_reason(@admin)
    lesson.confirm!(by: @admin)
    assert_equal [ lesson ], Chat::Memory.for_review(@workspace, [])
  end

  test "an edit replaces it with a lesson approved by the editor and keeps the old words as rejected, and the same words only change strictness" do
    lesson = taught("Checkout reads from the replica")

    edited = lesson.edit_lesson!(by: @admin, text: "Checkout reads from the primary", strict: true)

    assert_equal Chat::Memory::STATE_REJECTED, lesson.reload.state
    assert_equal edited, lesson.replaced_by
    assert_equal [ "Checkout reads from the primary", @incident, @admin, true ], [ edited.text, edited.source, edited.approved_by, edited.strict ]
    assert edited.approved_lesson?

    assert_equal edited, edited.edit_lesson!(by: @admin, text: "Checkout reads from the primary", strict: false)
    assert_not edited.reload.strict
    assert_nil lesson.edit_lesson!(by: @admin, text: "Anything", strict: false)
  end

  test "turning it down rejects it so reviews and Halon stop using it" do
    lesson = taught("Deploys on Fridays fail")
    lesson.approve!(by: @admin)

    assert_nil lesson.turn_down!(by: @member)
    assert lesson.turn_down!(by: @admin, reason: "One off")

    assert_equal [ Chat::Memory::STATE_REJECTED, "One off", @admin ], [ lesson.state, lesson.state_reason, lesson.rejected_by ]
    assert_equal Chat::Memory::Lesson::STATUS_TURNED_DOWN, lesson.lesson_status
    assert_empty Chat::Memory.for_review(@workspace, [])
  end

  test "a review reads the lessons about what the change touches first, then the workspace wide ones, then the rest" do
    auth = catalog_entries(:auth_service)
    wide = taught("Deploys happen from main")
    about = taught("Auth Service keeps sessions in Redis", subject: auth)
    elsewhere = taught("Platform team owns the queue", subject: catalog_entries(:platform_team))
    [ elsewhere, wide, about ].each { |lesson| lesson.approve!(by: @admin) }

    assert_equal [ about, wide, elsewhere ], Chat::Memory.for_review(@workspace, [ auth ])
  end

  private

  def taught(text, subject: nil)
    Chat::Memory.create!(workspace: @workspace, text: text, subject: subject, source: @incident, state: Chat::Memory::STATE_UNCONFIRMED)
  end
end

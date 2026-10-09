require "test_helper"

class Chat::Memory::RemindersTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "a person is reminded of what they taught, the incident's channel of what it taught, and the admins of what has no channel" do
    taught = waiting("Checkout reads from the replica", added_by: @bob, source: Conversation.start_personal!(workspace: @workspace, member: @bob))
    from_incident = waiting("A 5xx after a deploy has meant a full disk", source: @incident)
    from_nowhere = waiting("Backups run nightly")
    waiting("Learned yesterday", source: @incident, at: 1.day.ago)
    Chat::Memory.create!(workspace: @workspace, text: "Confirmed already", state: Chat::Memory::STATE_CONFIRMED, created_at: 10.days.ago)

    assert_equal [ [ nil, @incident, [ from_incident ] ] ], shape(Chat::Memory::Reminders.in_channels(@workspace))
    assert_equal [ [ @bob, nil, [ taught ] ], [ @admin, nil, [ from_nowhere ] ] ], shape(Chat::Memory::Reminders.direct(@workspace)).sort_by { |row| row.first == @bob ? 0 : 1 }
  end

  test "what a channel could not take goes to the admins, after anything the admin taught themselves" do
    own = waiting("The worker drains on deploy", added_by: @admin)
    from_incident = waiting("A 5xx after a deploy has meant a full disk", source: @incident)

    assert_equal [ [ @admin, nil, [ own, from_incident ] ] ], shape(Chat::Memory::Reminders.direct(@workspace, unposted: [ from_incident ]))
  end

  test "at most one message a week each, and never the same memory twice in a row" do
    first = waiting("Checkout reads from the replica", added_by: @bob)
    second = waiting("Checkout retries twice", added_by: @bob)
    Chat::MemoryPost.create!(workspace: @workspace, kind: Chat::MemoryPost::KIND_REMINDER, recipient: @bob, channel_id: "D1", memory_ids: [ first.id ],
                             created_at: 2.days.ago)

    assert_empty Chat::Memory::Reminders.direct(@workspace)
    assert_equal [ [ @bob, nil, [ second ] ] ], shape(Chat::Memory::Reminders.direct(@workspace, now: 6.days.from_now))

    Chat::MemoryPost.create!(workspace: @workspace, kind: Chat::MemoryPost::KIND_REMINDER, recipient: @bob, channel_id: "D1", memory_ids: [ first.id, second.id ])
    assert_empty Chat::Memory::Reminders.direct(@workspace, now: 7.days.from_now), "only memories shown last time wait, so nothing is sent"
  end

  private

  def waiting(text, added_by: nil, source: nil, at: 10.days.ago)
    Chat::Memory.create!(workspace: @workspace, text: text, state: Chat::Memory::STATE_UNCONFIRMED, added_by: added_by, source: source, created_at: at)
  end

  def shape(reminders) = reminders.map { |reminder| [ reminder.recipient, reminder.incident, reminder.memories ] }
end

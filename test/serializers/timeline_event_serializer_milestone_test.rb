require "test_helper"

class TimelineEventSerializerMilestoneTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "a note serializes its kind, statement, quote and link" do
    note(kind: "mitigation", statement: "Alice rolled back the 14:02 deploy")

    rendered = serialized.find { |event| event[:eventType] == IncidentEvent::MILESTONE_NOTED }

    assert_equal "noted", rendered[:description]
    assert_equal "mitigation", rendered.dig(:milestone, :kind)
    assert_equal "Alice rolled back the 14:02 deploy", rendered.dig(:milestone, :statement)
    assert_equal "rolling back", rendered.dig(:milestone, :quote)
    assert_equal "https://slack.test/p1", rendered.dig(:milestone, :permalink)
    assert_nil rendered[:subject]
  end

  test "the avatar comes from the person who said it, not from an actor" do
    note

    rendered = serialized.find { |event| event[:eventType] == IncidentEvent::MILESTONE_NOTED }

    assert_equal "Firefight", rendered[:actor]
    assert rendered[:automated]
    assert_equal @member.display_name, rendered.dig(:person, :name)
  end

  test "a note whose author has left the workspace still names them" do
    event = note
    event.update!(metadata: event.metadata.merge("member_id" => nil))

    rendered = serialized.find { |row| row[:eventType] == IncidentEvent::MILESTONE_NOTED }

    assert_equal @member.display_name, rendered.dig(:person, :name)
  end

  test "notes sit in the conversation, ordered by when the message was said" do
    note(statement: "Alice suspects the deploy", said_at: 3.hours.ago)
    note(statement: "Alice confirmed the lock", said_at: 1.hour.ago)
    @incident.incident_events.create!(event_type: IncidentEvent::MESSAGE_PINNED, created_at: 2.hours.ago, metadata: {})

    statements = serialized.filter_map { |event| event.dig(:milestone, :statement) }
    pinned_at = serialized.index { |event| event[:eventType] == IncidentEvent::MESSAGE_PINNED }

    assert_equal [ "Alice suspects the deploy", "Alice confirmed the lock" ], statements
    assert_operator serialized.index { |event| event.dig(:milestone, :statement) == "Alice suspects the deploy" },
                    :<, pinned_at
  end

  test "a dismissed note carries who dismissed it" do
    note.dismiss!(by: @member)

    rendered = serialized.find { |event| event[:eventType] == IncidentEvent::MILESTONE_NOTED }

    assert_not_nil rendered.dig(:milestone, :dismissedAt)
    assert_equal @member.display_name, rendered.dig(:milestone, :dismissedBy)
  end

  private

  def note(kind: "finding", statement: "Alice confirmed the pool is exhausted", said_at: 1.hour.ago)
    @incident.incident_events.create!(
      event_type: IncidentEvent::MILESTONE_NOTED,
      created_at: said_at,
      metadata: {
        kind: kind,
        statement: statement,
        member_id: @member.id,
        member_name: @member.display_name,
        member_avatar_url: @member.user.avatar_url,
        message_id: said_at.to_f.to_s,
        message_text: "rolling back",
        permalink: "https://slack.test/p1",
        said_at: said_at.utc.iso8601
      }
    )
  end

  def serialized
    TimelineEventSerializer.many(@incident.reload.timeline_events).map(&:deep_symbolize_keys)
  end
end

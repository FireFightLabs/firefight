require "test_helper"

class Api::V1::TranscriptsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @membership = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @workspace.update!(transcript_access_enabled: true)
  end

  # The reason it is its own resource: the full-access fixture key holds every
  # incident action and predates this, so it must not gain the conversation.
  test "a key granted incidents does not also read the transcript" do
    say "found it"

    get api_v1_incident_transcript_index_url(@incident), headers: api_headers

    assert_response :forbidden
  end

  test "a key granted the transcript ability reads it" do
    say "found it, the pooler ran out"
    _, token = create_service_key(
      workspace: @workspace, created_by: @membership, name: "Reader",
      permissions: { Ability::Action::RESOURCE_INCIDENT_TRANSCRIPTS => %w[read] }
    )

    get api_v1_incident_transcript_index_url(@incident), headers: api_headers(token: token)

    assert_response :success
    assert_equal [ "found it, the pooler ran out" ], json_response["messages"].map { |m| m["text"] }
    assert_equal @membership.actor_display_name, json_response["messages"].first.dig("said_by", "name")
  end

  test "a workspace that has not turned access on refuses a granted key" do
    @workspace.update!(transcript_access_enabled: false)
    say "found it"
    _, token = create_service_key(
      workspace: @workspace, created_by: @membership, name: "Reader",
      permissions: { Ability::Action::RESOURCE_INCIDENT_TRANSCRIPTS => %w[read] }
    )

    get api_v1_incident_transcript_index_url(@incident), headers: api_headers(token: token)

    assert_response :forbidden
    assert_equal "transcript_access_disabled", json_response.dig("error", "type")
  end

  test "a long conversation is walked backwards from the end" do
    5.times { |i| say "message #{i}", at: (5 - i).minutes.ago }
    _, token = create_service_key(
      workspace: @workspace, created_by: @membership, name: "Reader",
      permissions: { Ability::Action::RESOURCE_INCIDENT_TRANSCRIPTS => %w[read] }
    )

    get api_v1_incident_transcript_index_url(@incident, limit: 2), headers: api_headers(token: token)
    assert_equal [ "message 3", "message 4" ], json_response["messages"].map { |m| m["text"] }

    get api_v1_incident_transcript_index_url(@incident, limit: 2, before: json_response["more_before"]),
        headers: api_headers(token: token)
    assert_equal [ "message 1", "message 2" ], json_response["messages"].map { |m| m["text"] }
  end

  private

  def say(text, at: 1.minute.ago)
    IncidentTranscriptMessage.create!(
      workspace: @workspace, incident: @incident, message_id: "17#{rand(10**8)}.#{rand(9999)}",
      platform_user_id: @membership.platform_user_id, workspace_membership: @membership,
      content: text, posted_at: at
    )
  end
end

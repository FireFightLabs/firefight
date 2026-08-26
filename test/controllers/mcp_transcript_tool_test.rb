require "test_helper"

# Reading what people said in an incident channel. Two things have to be true
# before a single message comes back: the caller holds the transcript ability,
# which is separate from incidents on purpose, and the workspace has turned
# access on.
class McpTranscriptToolTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @membership = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @workspace.update!(transcript_access_enabled: true)

    _, @personal_token = ApiKey.create_with_token!(
      workspace: @workspace, created_by: @membership, on_behalf_of: @membership, name: "Personal"
    )
  end

  # The reason it is its own resource. A key granted incidents before this
  # existed must not silently gain the conversation.
  test "a key granted every incident action still cannot read the transcript" do
    say "found it, the pooler ran out"
    _, token = create_service_key(
      workspace: @workspace, created_by: @membership, name: "Incident bot",
      permissions: { Ability::Action::RESOURCE_INCIDENTS => %w[read create update delete] }
    )

    _, is_error, text = call_tool(Mcp::Tools::GET_INCIDENT_TRANSCRIPT,
                                  { incident: @incident.identifier }, token: token)

    assert is_error
    assert_match(/incident_transcripts/, text)
  end

  test "a key granted the transcript ability reads it" do
    say "found it, the pooler ran out"
    _, token = create_service_key(
      workspace: @workspace, created_by: @membership, name: "Reader",
      permissions: { Ability::Action::RESOURCE_INCIDENT_TRANSCRIPTS => %w[read] }
    )

    content, is_error = call_tool(Mcp::Tools::GET_INCIDENT_TRANSCRIPT,
                                  { incident: @incident.identifier }, token: token)

    assert_not is_error, content.inspect
    assert_equal [ "found it, the pooler ran out" ], content["messages"].map { |m| m["text"] }
  end

  # A grant is not enough. The workspace has to have decided.
  test "a workspace that has not turned access on refuses even an admin" do
    @workspace.update!(transcript_access_enabled: false)
    say "found it"

    _, is_error, text = call_tool(Mcp::Tools::GET_INCIDENT_TRANSCRIPT, { incident: @incident.identifier })

    assert is_error
    assert_match(/has not turned on transcript access/, text)
  end

  test "messages come back oldest first, with who said them" do
    say "first", at: 3.minutes.ago
    say "second", at: 2.minutes.ago
    say "third", at: 1.minute.ago

    content, = call_tool(Mcp::Tools::GET_INCIDENT_TRANSCRIPT, { incident: @incident.identifier })

    assert_equal %w[first second third], content["messages"].map { |m| m["text"] }
    assert_equal @membership.display_name, content["messages"].first["said_by"]
  end

  test "a long conversation is walked backwards from the end" do
    5.times { |i| say "message #{i}", at: (5 - i).minutes.ago }

    content, = call_tool(Mcp::Tools::GET_INCIDENT_TRANSCRIPT, { incident: @incident.identifier, limit: 2 })
    assert_equal [ "message 3", "message 4" ], content["messages"].map { |m| m["text"] }

    earlier, = call_tool(Mcp::Tools::GET_INCIDENT_TRANSCRIPT, {
      incident: @incident.identifier, limit: 2, before: content["more_before"]
    })
    assert_equal [ "message 1", "message 2" ], earlier["messages"].map { |m| m["text"] }
  end

  # A cursor that always came back meant a caller walking the conversation
  # never learned it had reached the start.
  test "the first page of a short conversation offers nothing before it" do
    say "all there is"

    content, = call_tool(Mcp::Tools::GET_INCIDENT_TRANSCRIPT, { incident: @incident.identifier })

    assert_nil content["more_before"]
  end

  # Slack stamps to the millisecond, so two people typing at once share a
  # posted_at. Paging on that alone would drop whichever one the cursor was not.
  test "messages said in the same instant survive paging" do
    same = 2.minutes.ago
    say "later", at: 1.minute.ago, message_id: "1700000000.0003"
    say "tied second", at: same, message_id: "1700000000.0002"
    say "tied first", at: same, message_id: "1700000000.0001"

    content, = call_tool(Mcp::Tools::GET_INCIDENT_TRANSCRIPT, { incident: @incident.identifier, limit: 2 })
    assert_equal [ "tied second", "later" ], content["messages"].map { |m| m["text"] }

    earlier, = call_tool(Mcp::Tools::GET_INCIDENT_TRANSCRIPT, {
      incident: @incident.identifier, limit: 2, before: content["more_before"]
    })
    assert_equal [ "tied first" ], earlier["messages"].map { |m| m["text"] }
    assert_nil earlier["more_before"]
  end

  test "the limit is capped rather than trusted" do
    say "only one"

    content, is_error = call_tool(Mcp::Tools::GET_INCIDENT_TRANSCRIPT, {
      incident: @incident.identifier, limit: 100_000
    })

    assert_not is_error, content.inspect
    assert_equal 1, content["messages"].size
  end

  # Scrubbing happens on the way in, so a redacted message is marked as one
  # rather than looking like what was typed.
  test "a redacted message says it was redacted" do
    IncidentTranscriptMessage.create!(
      workspace: @workspace, incident: @incident, message_id: "1700000000.9999",
      platform_user_id: @membership.platform_user_id, workspace_membership: @membership,
      content: "the key is [REDACTED]", posted_at: 1.minute.ago, scrubbed: true
    )

    content, = call_tool(Mcp::Tools::GET_INCIDENT_TRANSCRIPT, { incident: @incident.identifier })

    assert content["messages"].first["redacted"]
  end

  # By id, since identifiers restart per workspace and INC-1 exists in both.
  test "another workspace's incident is not reachable" do
    _, is_error = call_tool(Mcp::Tools::GET_INCIDENT_TRANSCRIPT, { incident: incidents(:active_p0_ws2).id })

    assert is_error
  end

  private

  def say(text, at: 1.minute.ago, message_id: "17#{rand(10**8)}.#{rand(9999)}")
    IncidentTranscriptMessage.create!(
      workspace: @workspace, incident: @incident, message_id: message_id,
      platform_user_id: @membership.platform_user_id, workspace_membership: @membership,
      content: text, posted_at: at
    )
  end

  def rpc(method, params = {}, id: 1, token: @personal_token)
    post mcp_path,
         params: { jsonrpc: "2.0", id: id, method: method, params: params }.to_json,
         headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{token}" }
    JSON.parse(response.body)
  end

  def call_tool(name, arguments = {}, token: @personal_token)
    result = rpc("tools/call", { name: name, arguments: arguments }, token: token).fetch("result")
    [ result["structuredContent"] || {}, result["isError"], result.dig("content", 0, "text") ]
  end
end

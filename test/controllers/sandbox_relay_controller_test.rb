require "test_helper"

class SandboxRelayControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    @conversation.chat_record
    @turn = Conversation::Turn.new(@conversation, asker: @member)
    fake = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "fake", name: "Fake")
    fake.integration_environments.create!(credentials: { token: "x" }.to_json)
    @reads = fake.tools.create!(name: "echo_text", description: "Echoes text back", read_only: true, enabled: true,
                                params_schema: { "type" => "object", "properties" => { "text" => { "type" => "string" } } })
    Integrations::NativePack.stubs(:for).with("fake").returns(FakeNativePack)
    @session, @token = Chat::TerminalSession.open!(@turn, changes: false, lasts: 60.seconds)
  end

  test "ff lists the tools, reads one's arguments and calls it on the command's token" do
    get "/sandbox_relay/tools", params: { q: "echo" }, headers: auth
    assert_response :success
    assert_equal [ @reads.model_facing_name ], response.parsed_body["tools"].map { |tool| tool["name"] }

    get "/sandbox_relay/tools/#{@reads.model_facing_name}", headers: auth
    assert_equal "Echoes text back", response.parsed_body["description"]

    post "/sandbox_relay/tools/#{@reads.model_facing_name}", params: { arguments: { text: "hi" } }.to_json, headers: auth.merge("CONTENT_TYPE" => "application/json")
    assert_response :success
    assert_equal({ "outcome" => "ok", "text" => "echo: hi" }, response.parsed_body)
  end

  test "an unknown tool is a 404, and a token that ended or never was reaches nothing" do
    get "/sandbox_relay/tools/nope", headers: auth
    assert_response :not_found

    @session.finish!
    get "/sandbox_relay/tools", headers: auth
    assert_response :unauthorized
    assert_equal Chat::TerminalSession::ENDED, response.parsed_body["error"]

    get "/sandbox_relay/clis", headers: { "Authorization" => "Bearer made-up" }
    assert_response :unauthorized
  end

  test "a provider's command line tool is answered with the status and body the relay gives" do
    Chat::Terminal::Relay.any_instance.expects(:api).with("acme", "GET", "v1/projects/shop/services", { "per_page" => "5" }, nil)
                         .returns(Chat::Terminal::Relay::Answered.new(status: 200, body: { "data" => [] }))

    get "/sandbox_relay/api/acme/v1/projects/shop/services", params: { per_page: 5 }, headers: auth

    assert_response :success
    assert_equal({ "data" => [] }, response.parsed_body)
  end

  private

  def auth = { "Authorization" => "Bearer #{@token}" }
end

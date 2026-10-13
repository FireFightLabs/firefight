require "test_helper"

class Api::V1::SkillsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::CUSTOM_SKILLS)
    _, @token = ApiKey.create_with_token!(workspace: @workspace, created_by: @admin, on_behalf_of: @admin, name: "Personal")
    @skill = Chat::CustomSkill.create_with!(workspace: @workspace, name: "game_day", by: @admin,
                                            content: { "when" => "Someone asks for a game day", "tools" => [ "declare_incident" ], "steps" => "1. Declare it." })
  end

  test "lists the skills without their steps, and shows one whole" do
    get api_v1_skills_url, headers: api_headers(token: @token)
    assert_response :success
    listed = json_response["skills"].sole
    assert_equal [ "game_day", true, 1 ], listed.values_at("name", "enabled", "version")
    assert_not listed.key?("steps")

    get api_v1_skill_url(@skill), headers: api_headers(token: @token)
    assert_equal [ "1. Declare it.", @skill.live_version_id ], json_response["skill"].values_at("steps", "version_id")
  end

  test "creates a skill, updates it as a new version, refuses one over someone else's, switches it off and deletes it" do
    post api_v1_skills_url, params: { name: "rotate_keys", when: "Rotating keys", tools: [ "declare_incident" ], steps: "1. Declare." }.to_json,
                            headers: api_headers(token: @token)
    assert_response :created
    created = Chat::CustomSkill.find(json_response.dig("skill", "id"))

    seen = created.live_version_id
    patch api_v1_skill_url(created), params: { steps: "1. Page first.", version_id: seen }.to_json, headers: api_headers(token: @token)
    assert_response :success
    assert_equal 2, json_response.dig("skill", "version")

    patch api_v1_skill_url(created), params: { steps: "Over it", version_id: seen }.to_json, headers: api_headers(token: @token)
    assert_response :conflict

    patch api_v1_skill_url(created), params: { enabled: false }.to_json, headers: api_headers(token: @token)
    assert_equal false, json_response.dig("skill", "enabled")

    post api_v1_skills_url, params: { name: "bad", when: "x", tools: [ "launch_rockets" ], steps: "1." }.to_json, headers: api_headers(token: @token)
    assert_response :unprocessable_entity
    assert_match "launch_rockets is not a tool", response.body

    delete api_v1_skill_url(created), headers: api_headers(token: @token)
    assert_response :no_content
  end

  test "an enabled that is not true or false is refused and the skill stays as it was" do
    patch api_v1_skill_url(@skill), params: { enabled: "flase" }.to_json, headers: api_headers(token: @token)

    assert_response :unprocessable_entity
    assert_equal "enabled should be true or false.", json_response.dig("error", "message")
    assert @skill.reload.enabled?

    patch api_v1_skill_url(@skill), params: { enabled: "false" }.to_json, headers: api_headers(token: @token)
    assert_response :success
    assert_not @skill.reload.enabled?
  end

  test "a skill created with enabled false starts switched off, and an enabled that is not true or false makes nothing" do
    post api_v1_skills_url, params: { name: "rotate_keys", when: "Rotating keys", tools: [ "declare_incident" ], steps: "1. Declare.", enabled: false }.to_json,
                            headers: api_headers(token: @token)
    assert_response :created
    assert_equal false, json_response.dig("skill", "enabled")
    assert_not Chat::CustomSkill.find(json_response.dig("skill", "id")).enabled?

    assert_no_difference -> { Chat::CustomSkill.where(workspace: @workspace).count } do
      post api_v1_skills_url, params: { name: "drain", when: "Draining", tools: [], steps: "1. Drain.", enabled: "flase" }.to_json,
                              headers: api_headers(token: @token)
    end
    assert_response :unprocessable_entity
    assert_equal "enabled should be true or false.", json_response.dig("error", "message")
  end

  test "a skill a workflow runs is not deleted" do
    Workflow.create!(workspace: @workspace, name: "Drill").open_draft!(by: @admin)
            .update_columns(steps: [ { "id" => "step_1", "name" => "drill", "kind" => "run_skill", "config" => { "skill" => "game_day" } } ])

    delete api_v1_skill_url(@skill), headers: api_headers(token: @token)

    assert_response :unprocessable_entity
    assert_match "take it out of that workflow", response.body
  end

  test "without the custom skills flag the endpoints do not exist" do
    FeatureFlags.disable!(@workspace, FeatureFlags::CUSTOM_SKILLS)

    get api_v1_skills_url, headers: api_headers(token: @token)

    assert_response :not_found
  end
end

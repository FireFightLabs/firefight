require "test_helper"

class WorkspaceAiAccountSerializerTest < ActiveSupport::TestCase
  test "what the page is sent never holds a credential, only the settings that are not secrets" do
    workspace = workspaces(:slack_workspace_one)
    bedrock = add_ai_account!(workspace, provider: "bedrock", key: "AKIASECRETACCESS", settings: {
      "secret_key" => "bedrock-secret-value", "session_token" => "bedrock-session-token", "region" => "eu-west-1"
    })
    vertex = add_ai_account!(workspace, provider: "vertexai", key: nil, settings: {
      "project_id" => "acme", "location" => "us-central1",
      "service_account_key" => { "client_email" => "halon@acme.iam.gserviceaccount.com", "private_key" => "-----BEGIN PRIVATE KEY-----abc" }.to_json
    })

    sent = WorkspaceAiAccountSerializer.many([ bedrock, vertex ]).to_json

    %w[AKIASECRETACCESS bedrock-secret-value bedrock-session-token PRIVATE KEY credentials].each do |secret|
      assert_not_includes sent, secret
    end
    shown = JSON.parse(sent)
    assert_equal({ "region" => "eu-west-1" }, shown.first["settings"])
    assert_equal "Access key ID ending in CESS. Enter a new one to replace it.", shown.first["keySummary"]
    assert_equal "Service account key (JSON) for halon@acme.iam.gserviceaccount.com. Enter a new one to replace it.", shown.last["keySummary"]
  end
end

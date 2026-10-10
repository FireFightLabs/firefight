require "test_helper"

# A read whose whole answer is a secret is refused before it runs, for every caller, and a secret beside what is worth
# reading is taken out of the answer.
class Integrations::SecretReadsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "a Cloudflare request for a tunnel's token is refused with what to read instead, written by Firefight or by hand" do
    execute = tool!("cloudflare", "execute")
    written = Integrations::ReadGuards::Cloudflare.arguments_for({ "method" => "GET", "path" => "/accounts/abc/cfd_tunnel/t1/token" }, nil)
    by_hand = { "code" => "async () => { const t = await cloudflare.request({ method: 'GET', path: '/accounts/abc/cfd_tunnel/t1/token' }); return t }" }

    [ written, by_hand ].each do |arguments|
      refusal = assert_raises(Integrations::PolicyRefusal) { Integrations::SecretReads.refuse!(execute, arguments) }
      assert_match "Read the tunnel itself", refusal.message
    end
    assert_nil Integrations::SecretReads.refusal(execute, Integrations::ReadGuards::Cloudflare.arguments_for({ "method" => "GET", "path" => "/accounts/abc/cfd_tunnel/t1" }, nil))
  end

  test "a KV value and an R2 object are refused, and their listings are not" do
    execute = tool!("cloudflare", "execute")

    assert Integrations::SecretReads.refusal(execute, { "code" => "cloudflare.request({ method: 'GET', path: '/accounts/a/storage/kv/namespaces/n/values/key' })" })
    assert Integrations::SecretReads.refusal(execute, { "code" => "cloudflare.request({ method: 'GET', path: '/accounts/a/r2/buckets/b/objects/backup.sql' })" })
    assert_nil Integrations::SecretReads.refusal(execute, { "code" => "cloudflare.request({ method: 'GET', path: '/accounts/a/storage/kv/namespaces/n/keys' })" })
  end

  test "Neon's connection string is never read, and the executor refuses before calling the server" do
    connection_string = tool!("neon", "get_connection_string")
    Integrations::McpClient.expects(:new).never

    refusal = assert_raises(Integrations::PolicyRefusal) do
      Integrations::McpExecutor.call(tool: connection_string, environment_row: connection_string.integration.integration_environments.first, arguments: {})
    end
    assert_match "holds the role's password", refusal.message
  end

  test "Cloudflare's secret fields and a tunnel token's shape are taken out of any answer" do
    answer = { "content" => [ { "type" => "text", "text" => {
      "result" => { "sitekey" => "0x4AAA", "secret" => "0x4AAAAsecretvalue", "destination_conf" => "s3://logs?secret-access-key=abc" },
      "token" => "eyJhIjoiYWJjMTIzIiwidCI6ImRlZiIsInMiOiJzZWNyZXQifQ=="
    }.to_json } ] }

    text = Integrations::Redactions.apply(answer, **Integrations::Redactions.rules("cloudflare"))["content"].first["text"]

    assert_includes text, "0x4AAA\""
    assert_not_includes text, "secretvalue"
    assert_not_includes text, "secret-access-key=abc"
    assert_not_includes text, "eyJhIjoiYWJjMTIzIiwidCI6ImRlZiIsInMiOiJzZWNyZXQifQ"
  end

  test "credentials of shapes the old patterns missed are redacted" do
    {
      "github_pat_11ABCDEFG0123456789_abcdefghijklmnopqrstuvwxyz" => "github_pat",
      "sb_secret_N7UND0UgjKTVK-Uodkm0Hg" => "supabase_secret",
      "https://hooks.slack.com/services/T000/B000/XXXX" => "slack_webhook",
      "Authorization: Bearer abcdefghijklmnop1234" => "bearer_token",
      "host=db user=app password=hunter22 dbname=app" => "password_setting",
      "$2b$12$#{'a' * 53}" => "bcrypt_hash",
      "SCRAM-SHA-256$4096:c2FsdA==$c3RvcmVk:c2VydmVy" => "scram_hash"
    }.each do |text, name|
      assert_includes Chat::SecretFree.redacted(text), "[REDACTED:#{name}]", text
    end
  end

  private

  def tool!(provider, name)
    integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: provider, name: provider.capitalize,
                                                  settings: { "server_url" => "https://mcp.example.com/mcp" })
    integration.integration_environments.create!
    integration.tools.create!(name: name, read_only: false, enabled: true, params_schema: {})
  end
end

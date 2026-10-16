require "test_helper"
require Rails.root.join("db/migrate/20261016172000_encrypt_outbound_webhook_signing_secrets")

# A webhook's signing secret is kept encrypted, shown once when it is made or replaced, and otherwise only as a hint.
class WebhookSigningSecretTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @webhook = webhooks(:active_webhook)
    sign_in(users(:alice), @workspace)
  end

  test "the secret is stored encrypted and read back for signing" do
    raw = Webhook.connection.select_value(Webhook.where(id: @webhook.id).select(:signing_secret).to_sql)

    assert_not_equal "test_signing_secret_abc123def456", raw
    assert_equal "test_signing_secret_abc123def456", @webhook.reload.signing_secret
    assert_equal "Secret ending in f456", @webhook.signing_secret_hint
  end

  test "a new webhook's secret is shown once, and the page otherwise carries only its hint" do
    post webhooks_url, params: { webhook: { name: "Receiver", url: "https://example.com/receive", subscribed_events: [ "incident.created" ] } }

    webhook = @workspace.webhooks.find_by!(name: "Receiver")
    assert_equal webhook.signing_secret, flash.inertia[:webhook_signing_secret]
    assert_equal "Receiver was created.", flash[:notice]

    get developer_webhooks_url, headers: inertia_headers
    assert_equal webhook.signing_secret, JSON.parse(response.body).dig("flash", "webhook_signing_secret"), "shown on the page the create lands on"

    get developer_webhooks_url, headers: inertia_headers
    row = inertia_props["webhooks"].find { |each| each["id"] == webhook.id }
    assert_equal "Secret ending in #{webhook.signing_secret.last(4)}", row["signingSecretHint"]
    assert_not_includes response.body, webhook.signing_secret
  end

  test "the secret is never read back on demand" do
    assert_raises(NameError) { signing_secret_webhook_url(@webhook) }
  end

  test "replacing the secret shows the new one once, says so, and the old one stops signing" do
    old = @webhook.signing_secret

    post rotate_signing_secret_webhook_url(@webhook)

    assert_redirected_to developer_webhooks_path
    assert_equal "Production Alerts has a new signing secret. The old one stopped working.", flash[:notice]
    assert_not_equal old, @webhook.reload.signing_secret
    assert_equal @webhook.signing_secret, flash.inertia[:webhook_signing_secret]
  end

  test "secrets saved before encryption are encrypted in place" do
    Webhook.where(id: @webhook.id).update_all(signing_secret: "plain_secret_from_before_0001")

    ActiveRecord::Migration.suppress_messages { EncryptOutboundWebhookSigningSecrets.new.migrate(:up) }

    raw = Webhook.connection.select_value(Webhook.where(id: @webhook.id).select(:signing_secret).to_sql)
    assert_not_equal "plain_secret_from_before_0001", raw
    assert_equal "plain_secret_from_before_0001", @webhook.reload.signing_secret
  end
end

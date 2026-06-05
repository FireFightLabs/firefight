require "test_helper"

class IncidentTranscriptMessageTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
  end

  test "belongs to workspace, incident, and optional membership" do
    message = build_message
    assert_equal @workspace, message.workspace
    assert_equal @incident, message.incident
    assert_equal @member, message.workspace_membership
  end

  test "workspace_membership is optional" do
    message = build_message(workspace_membership: nil)
    assert message.save
  end

  test "content round-trips through encryption" do
    message = build_message(content: "investigating db replica lag").tap(&:save!)
    assert_equal "investigating db replica lag", message.reload.content
  end

  test "raw DB column stores ciphertext, not plaintext" do
    message = build_message(content: "ssh into prod-3 and tail logs").tap(&:save!)

    raw = IncidentTranscriptMessage.connection.select_value(
      "SELECT content FROM incident_transcript_messages WHERE id = '#{message.id}'"
    )

    assert_not_equal "ssh into prod-3 and tail logs", raw
    assert_match(/\A\{.*\}\z/, raw, "expected AR::Encryption JSON envelope")
  end

  test "kept scope excludes soft-deleted rows" do
    kept = build_message(slack_ts: "1.001").tap(&:save!)
    build_message(slack_ts: "1.002", deleted_at: Time.current).tap(&:save!)

    assert_includes IncidentTranscriptMessage.kept, kept
    assert_equal 1, IncidentTranscriptMessage.kept.count
  end

  test "scrubbed defaults to false" do
    assert_equal false, build_message.tap(&:save!).reload.scrubbed
  end

  test "requires workspace, incident, slack_ts, slack_user_id, posted_at" do
    message = IncidentTranscriptMessage.new
    assert_not message.valid?
    %i[workspace incident slack_ts slack_user_id posted_at].each do |field|
      assert message.errors[field].any?, "expected presence error on #{field}"
    end
  end

  test "soft_delete! sets deleted_at" do
    message = build_message.tap(&:save!)
    assert_nil message.deleted_at
    message.soft_delete!
    assert_not_nil message.reload.deleted_at
  end

  test "scrubber replaces AWS key and flags scrubbed" do
    message = build_message(content: "creds AKIAIOSFODNN7EXAMPLE leaked").tap(&:save!)
    assert_equal "creds [REDACTED:aws_key] leaked", message.reload.content
    assert message.scrubbed
  end

  test "scrubber replaces multiple distinct patterns in one pass" do
    content = "aws AKIAIOSFODNN7EXAMPLE github ghp_abcdefghijklmnopqrstuvwxyz0123456789"
    message = build_message(content: content).tap(&:save!)
    decrypted = message.reload.content
    assert_includes decrypted, "[REDACTED:aws_key]"
    assert_includes decrypted, "[REDACTED:github_token]"
    assert message.scrubbed
  end

  test "scrubber leaves clean content alone and does not flag scrubbed" do
    message = build_message(content: "nothing sensitive here").tap(&:save!)
    assert_equal "nothing sensitive here", message.reload.content
    assert_not message.scrubbed
  end

  test "scrubber re-runs when content changes on update" do
    message = build_message(content: "clean").tap(&:save!)
    assert_not message.scrubbed

    message.update!(content: "AKIAIOSFODNN7EXAMPLE pasted")
    assert_equal "[REDACTED:aws_key] pasted", message.reload.content
    assert message.scrubbed
  end

  test "scrubber does not re-run when content is unchanged" do
    message = build_message(content: "clean").tap(&:save!)
    message.update!(scrubbed: false)
    message.update!(posted_at: 1.minute.from_now)
    assert_not message.reload.scrubbed
  end

  test "scrubber catches OpenAI, Anthropic, and Stripe keys" do
    samples = {
      openai_key:     "sk-proj-#{"a" * 60}",
      anthropic_key:  "sk-ant-api03-#{"X" * 90}",
      stripe_key:     "sk_live_#{"A" * 30}",
      stripe_webhook: "whsec_#{"b" * 40}"
    }

    samples.each do |label, secret|
      message = build_message(slack_ts: "ts-#{label}", content: "leaked #{secret} here").tap(&:save!)
      decrypted = message.reload.content
      assert_includes decrypted, "[REDACTED:#{label}]", "expected #{label} to be scrubbed"
      assert_not_includes decrypted, secret
      assert message.scrubbed
    end
  end

  test "scrubber catches Google, SendGrid, Twilio, and DigitalOcean keys" do
    samples = {
      google_api_key:     "AIza#{"A" * 35}",
      sendgrid_key:       "SG.#{"a" * 22}.#{"b" * 43}",
      twilio_key:         "SK#{"a" * 32}",
      digitalocean_token: "dop_v1_#{"a" * 64}"
    }

    samples.each do |label, secret|
      message = build_message(slack_ts: "ts-#{label}", content: "see #{secret}").tap(&:save!)
      assert_includes message.reload.content, "[REDACTED:#{label}]"
    end
  end

  test "scrubber catches npm, Hugging Face, and New Relic tokens" do
    samples = {
      npm_token:         "npm_#{"a" * 36}",
      huggingface_token: "hf_#{"x" * 40}",
      new_relic_key:     "NRAK-#{"A" * 27}"
    }

    samples.each do |label, secret|
      message = build_message(slack_ts: "ts-#{label}", content: "token #{secret}").tap(&:save!)
      assert_includes message.reload.content, "[REDACTED:#{label}]"
    end
  end

  test "scrubber catches PEM private key blocks across variants" do
    pem = <<~KEY.strip
      -----BEGIN RSA PRIVATE KEY-----
      MIIEpAIBAAKCAQEAxYz
      -----END RSA PRIVATE KEY-----
    KEY

    message = build_message(content: "key dump: #{pem}").tap(&:save!)
    assert_includes message.reload.content, "[REDACTED:private_key]"
    assert_not_includes message.reload.content, "MIIEpAIBAAKCAQEAxYz"
  end

  private

  def build_message(**overrides)
    IncidentTranscriptMessage.new({
      workspace: @workspace,
      incident: @incident,
      workspace_membership: @member,
      slack_ts: "1717420800.000100",
      slack_user_id: "U_TEST",
      content: "hello world",
      posted_at: Time.current
    }.merge(overrides))
  end
end

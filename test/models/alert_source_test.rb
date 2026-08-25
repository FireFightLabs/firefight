require "test_helper"

class AlertSourceTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "generates endpoint_path and secret_token on create" do
    source = AlertSource.create!(workspace: @workspace, name: "Datadog prod", provider: AlertSource::PROVIDER_GENERIC)

    assert source.endpoint_path.present?
    assert source.secret_token.present?
    assert_equal AlertProviders::Generic, AlertProviders.for(source.provider)
  end

  test "name is unique per workspace" do
    AlertSource.create!(workspace: @workspace, name: "Monitoring", provider: AlertSource::PROVIDER_GENERIC)
    duplicate = AlertSource.new(workspace: @workspace, name: "Monitoring", provider: AlertSource::PROVIDER_GENERIC)

    assert_not duplicate.valid?
  end

  test "resolve_severity uses the per-source map with workspace default fallback" do
    critical = @workspace.incident_severities.active.order(:rank).first
    source = AlertSource.create!(
      workspace: @workspace, name: "Mapped", provider: AlertSource::PROVIDER_GENERIC,
      config: { "severity_map" => { "p1" => critical.id } }
    )

    assert_equal critical, source.resolve_severity("P1")
    assert_equal @workspace.incident_severities.default_severity, source.resolve_severity("weird-unknown")
  end

  test "rate limit defaults and honors config override" do
    source = AlertSource.new(workspace: @workspace, name: "X", provider: AlertSource::PROVIDER_GENERIC)
    assert_equal AlertSource::DEFAULT_RATE_LIMIT_PER_MINUTE, source.rate_limit_per_minute

    source.config = { "rate_limit_per_minute" => 5 }
    assert_equal 5, source.rate_limit_per_minute
  end
end

require "test_helper"
require Rails.root.join("db/migrate/20261004140000_move_devin_acu_limit_to_max_acus")

class MoveDevinAcuLimitToMaxAcusTest < ActiveSupport::TestCase
  setup do
    devin = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_NATIVE, provider: "devin", name: "Devin", slug: "devin")
    @in_credentials = devin.integration_environments.create!(credentials: { "api_key" => "cog_key", "acu_limit" => "12" }.to_json)
    @in_fields = devin.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { "api_key" => "cog_other" }.to_json,
                                                        base_config: { IntegrationEnvironment::FIELDS_KEY => { "organization" => "org-abc", "acu_limit" => "8" } })
  end

  test "a limit kept in the credentials or under the old field name moves to max_acus, and moves back as a field" do
    migrate(:up)

    assert_equal({ "api_key" => "cog_key" }, @in_credentials.reload.credentials_hash)
    assert_equal({ "max_acus" => "12" }, @in_credentials.fields)
    assert_equal({ "organization" => "org-abc", "max_acus" => "8" }, @in_fields.reload.fields)

    migrate(:down)
    assert_equal({ "organization" => "org-abc", "acu_limit" => "8" }, @in_fields.reload.fields)
  end

  private

  def migrate(direction) = ActiveRecord::Migration.suppress_messages { MoveDevinAcuLimitToMaxAcus.new.migrate(direction) }
end

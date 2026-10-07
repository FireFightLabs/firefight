require "test_helper"
require Rails.root.join("db/migrate/20261007210300_keep_northflank_and_railway_projects_as_lists")

# What a connection reaching several of what its provider names a scope (Northflank projects here) says to a person and
# to Halon, and how a project kept from before reads.
class Integrations::ScopesTest < ActiveSupport::TestCase
  ALL = IntegrationProvider::ConnectField::ALL

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @faylee = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Faylee")
    @row = @faylee.integration_environments.create!(credentials: { "api_token" => "nf" }.to_json)
    @row.store_fields!("project" => %w[faylee acme])
    @field = IntegrationProvider.find("northflank").scope_field
  end

  test "a scope field holds a list, all alone, and is refused empty" do
    assert @field.multiple
    assert_equal %w[faylee acme], @field.value_of([ " faylee ", "acme", "" ])
    assert_equal [ ALL ], @field.value_of([ "faylee", ALL ])
    assert_equal "Choose at least one project, or all the token can read.", @field.refusal([])
    assert_nil @field.refusal(%w[anything-the-token-lists])
    assert_equal IntegrationProvider::ConnectField::ALL_LABEL, @field.shown([ ALL ])
    assert_raises(ArgumentError) { IntegrationProvider::ConnectField.new(key: "p", label: "P", hint: "", scope: true, path: true) }
  end

  test "what a connection reaches reads one project, several, or every one the token can read" do
    assert_equal "Faylee (Northflank), projects faylee and acme", @faylee.target_label
    assert_equal "Faylee (Northflank), project acme", @faylee.target_label(@row, scope: "acme")

    @row.store_fields!("project" => [ ALL ])
    assert_equal "Faylee (Northflank), every project the token can read", @faylee.reload.target_label
  end

  test "words naming another project of the same connection refuse the call, and words naming its own pass" do
    refused = Chat::Tools::Target.scope_misdirection(@row, "faylee", "Scale acme's web to zero", called: "faylee_api_request") do |named, field|
      "Call it with #{field.key} #{named}."
    end

    assert_equal "Not run, and nobody was asked. faylee_api_request reaches Faylee (Northflank), project faylee, but what you wrote names " \
                 "project acme. Call it with project acme. Never run a call in one project for another's.", refused
    assert_nil Chat::Tools::Target.scope_misdirection(@row, "faylee", "Scale faylee's web, not acme's", called: "x") { "" }
    assert_nil Chat::Tools::Target.scope_misdirection(@row, "faylee", "Scale web to zero", called: "x") { "" }

    @row.store_fields!("project" => %w[faylee])
    assert_nil Chat::Tools::Target.scope_misdirection(@row.reload, "faylee", "Scale acme's web", called: "x") { "" }, "one project names nothing else"
  end

  test "a step, the activity log and an approval name the project a call reached" do
    tool = @faylee.tools.create!(name: "api_request", read_only: false, enabled: true, params_schema: {})

    assert_equal "Api request · Faylee (Northflank), project acme", Chat::Tools.step(tool.model_facing_name, { "project" => "acme" }, workspace: @workspace).title
    assert_equal "Api request · Faylee (Northflank)", Chat::Tools.step(tool.model_facing_name, {}, workspace: @workspace).title
    invocation = Ability::Invocation.new(workspace: @workspace, action_key: tool.action_key, params: { "project" => "acme" })
    assert_equal "Faylee (Northflank), project acme", invocation.connection_name
  end

  test "a project kept as one string reads as a list of it, and the migration keeps it as one" do
    @row.store_fields!("project" => " faylee ")
    railway = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "railway", name: "Railway")
                        .integration_environments.create!
    railway.store_fields!("project" => "prj-1", "environment" => "production")
    other = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "google_cloud", name: "GCP").integration_environments.create!
    other.store_fields!("project" => "my-project")

    assert_equal [ " faylee " ], Integrations::ConnectionSettings.of(@row).chosen_scopes
    migrate(:up)
    assert_equal [ "faylee" ], @row.reload.fields["project"]
    assert_equal({ "project" => [ "prj-1" ], "environment" => "production" }, railway.reload.fields)
    assert_equal "my-project", other.reload.fields["project"], "another provider's project is left alone"

    migrate(:down)
    assert_equal "faylee", @row.reload.fields["project"]
    assert_equal "prj-1", railway.reload.fields["project"]
  end

  private

  def migrate(direction) = ActiveRecord::Migration.suppress_messages { KeepNorthflankAndRailwayProjectsAsLists.new.migrate(direction) }
end

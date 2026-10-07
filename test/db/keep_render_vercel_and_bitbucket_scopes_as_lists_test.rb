require "test_helper"
require Rails.root.join("db/migrate/20261007210500_keep_render_vercel_and_bitbucket_scopes_as_lists")

class KeepRenderVercelAndBitbucketScopesAsListsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @render = row("render", { "workspace" => " tea-1 " })
    @vercel = row("vercel", { "team" => "acme" })
    @personal = row("vercel", {}, name: "Vercel personal")
    @bitbucket = row("bitbucket", { "workspace" => "acme" })
    @other = row("fly", { "organization" => "my-org" })
  end

  test "each workspace or team becomes a list of it, a Vercel row without a team keeps none, and it moves back" do
    migrate(:up)

    assert_equal [ "tea-1" ], @render.reload.fields["workspace"]
    assert_equal [ "acme" ], @vercel.reload.fields["team"]
    assert_empty @personal.reload.fields, "no team still reads the token's own account"
    assert_equal [ "acme" ], @bitbucket.reload.fields["workspace"]
    assert_equal "my-org", @other.reload.fields["organization"], "another provider's field is left alone"

    migrate(:down)
    assert_equal [ "tea-1", "acme", "acme" ], [ @render.reload.fields["workspace"], @vercel.reload.fields["team"], @bitbucket.reload.fields["workspace"] ]
  end

  private

  def row(provider, fields, name: provider)
    environment_row = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: provider, name: name).integration_environments.create!
    environment_row.store_fields!(fields)
    environment_row
  end

  def migrate(direction) = ActiveRecord::Migration.suppress_messages { KeepRenderVercelAndBitbucketScopesAsLists.new.migrate(direction) }
end

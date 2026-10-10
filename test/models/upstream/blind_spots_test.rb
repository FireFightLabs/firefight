require "test_helper"

class Upstream::BlindSpotsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @row = integration.integration_environments.create!
    @web = ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: "web-id",
                                         name: "web", integration_environment: @row, first_seen_at: 1.day.ago, last_seen_at: Time.current)
  end

  test "a setting named for a system or pointing at its host names it, with how to read it when Firefight cannot connect it" do
    use!("STRIPE_SECRET_KEY")
    use!("AUTH_ISSUER_URL", ResourceMap::Use.of("web", "AUTH_ISSUER_URL", "https://acme.auth0.com/", @workspace))

    spots = Upstream::BlindSpots.new(@workspace, @admin).spots.index_by { |spot| spot.entry.name }

    assert_equal [ "web's setting STRIPE_SECRET_KEY is named for it" ], spots["Stripe"].evidence
    assert_equal [ "web's setting AUTH_ISSUER_URL points at auth0.com" ], spots["Auth0"].evidence
    assert_match "Firefight has no connection for Auth0, so Halon cannot read its logs", spots["Auth0"].how
    assert_match "Its status page is https://status.auth0.com, which check_status_page reads.", spots["Auth0"].how
  end

  test "a provider Firefight connects says how to connect it, and one already connected is no blind spot" do
    use!("NEON_DATABASE_URL")
    @workspace.catalog_entries.create!(catalog_type: catalog_types(:team_ws1), name: "GitHub", slug: "github")

    spots = Upstream::BlindSpots.new(@workspace, @admin).spots.index_by { |spot| spot.entry.name }

    assert_match "Connect Neon in Integrations", spots["Neon"].how
    assert_match "connect=neon", spots["Neon"].how
    assert_equal [ "The catalog lists GitHub" ], spots["GitHub"].evidence
    use!("NF_API_URL", ResourceMap::Use.of("web", "NF_API_URL", "https://api.northflank.com/v1", @workspace))
    assert_nil Upstream::BlindSpots.new(@workspace, @admin).spots.find { |spot| spot.entry.key == "northflank" }
  end

  test "only systems of the kind asked for, and none from resources the reader may not see" do
    use!("STRIPE_SECRET_KEY")
    use!("CLERK_SECRET_KEY")

    assert_equal [ "Clerk" ], Upstream::BlindSpots.new(@workspace, @admin, category: "Sign-in").spots.map { |spot| spot.entry.name }
    ResourceMap::Resource.stubs(:visible_to).returns(ResourceMap::Resource.none)
    assert_empty Upstream::BlindSpots.new(@workspace, @admin).spots
  end

  private

  def use!(variable, found = nil)
    found ||= ResourceMap::Use.named("web", variable)
    ResourceMap::Use.create!(workspace: @workspace, resource: @web, integration_environment: @row, variable: variable, fingerprint: found.fingerprint,
                             domain_fingerprint: found.domain_fingerprint, last_seen_at: Time.current)
  end
end

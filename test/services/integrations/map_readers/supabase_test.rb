require "test_helper"

module Integrations
  module MapReaders
    class SupabaseTest < ActiveSupport::TestCase
      PROJECTS = { "projects" => [ { "id" => "abcdefghijklmnopqrst", "ref" => "abcdefghijklmnopqrst", "organization_id" => "org1", "organization_slug" => "acme",
                                     "name" => "shop", "status" => "ACTIVE_HEALTHY", "region" => "us-east-1", "created_at" => "2026-01-01T00:00:00Z",
                                     "database" => { "version" => "15.8.1" } } ] }.freeze
      BRANCHES = { "branches" => [
        { "id" => "b1", "name" => "main", "project_ref" => "abcdefghijklmnopqrst", "parent_project_ref" => "abcdefghijklmnopqrst", "is_default" => true,
          "persistent" => true, "status" => "FUNCTIONS_DEPLOYED" },
        { "id" => "b2", "name" => "feature", "project_ref" => "zyxwvutsrqponmlkjihg", "parent_project_ref" => "abcdefghijklmnopqrst", "is_default" => false,
          "git_branch" => "feature/checkout", "persistent" => false, "status" => "MIGRATIONS_FAILED" }
      ] }.freeze

      test "every project is a database, and each branch is a project of its own linked to it" do
        snapshot = Supabase.new(settings) { |tool, _arguments| answer(tool) }.map

        project, main, feature = snapshot.resources
        assert_equal [ "supabase", "acme", ResourceMap::KIND_DATABASE, "abcdefghijklmnopqrst" ], project.key
        assert_equal [ "ACTIVE_HEALTHY", "https://supabase.com/dashboard/project/abcdefghijklmnopqrst" ], [ project.status, project.url ]
        assert_equal({ "engine" => "Postgres 15.8.1", "region" => "us-east-1" }, project.details)
        assert main.details[ResourceMap::PRODUCTION]
        assert_equal [ ResourceMap::KIND_BRANCH, "zyxwvutsrqponmlkjihg", "shop/feature", "MIGRATIONS_FAILED" ], [ feature.kind, feature.external_id, feature.name, feature.status ]
        assert_equal "https://supabase.com/dashboard/project/zyxwvutsrqponmlkjihg", feature.url
        assert_equal "feature/checkout", feature.details["branch"]
        assert_equal [ ResourceMap::RELATION_BRANCH_OF ] * 2, snapshot.links.map(&:relation)
        words = Integrations::Provider.for(Supabase::PROVIDER)
        assert_equal ResourceMap::Resource::HEALTH_FAILING, ResourceMap::Resource.new(status: words.status_of(feature.status)).health
        assert_equal ResourceMap::Resource::HEALTH_OK, ResourceMap::Resource.new(status: words.status_of(project.status)).health
        assert_equal ResourceMap::Resource::HEALTH_BUSY, ResourceMap::Resource.new(status: words.status_of("INACTIVE")).health
      end

      test "a list switched off, or one Supabase refuses, is a gap in the map" do
        off = Supabase.new { |tool, _arguments| tool == Supabase::LIST_PROJECTS ? nil : answer(tool) }.map
        assert_equal [ [ "list_projects is switched off for Supabase, so the projects are not on the map.", [ ResourceMap::KIND_DATABASE, ResourceMap::KIND_BRANCH ] ] ],
                     off.gaps.map { |gap| [ gap.text, gap.kinds ] }
        assert_equal [ ResourceMap::KIND_DATABASE, ResourceMap::KIND_BRANCH ], off.unread_kinds

        refused = Supabase.new do |tool, _arguments|
          tool == Supabase::LIST_BRANCHES ? { "isError" => true, "content" => [ { "type" => "text", "text" => "Failed to list branches" } ] } : answer(tool)
        end.map
        assert_equal [ "Supabase refused to list the branches of shop: Failed to list branches." ], refused.gaps.map(&:text)
        assert_equal [ ResourceMap::KIND_DATABASE ], refused.resources.map(&:kind)
      end

      test "a bare list is read like a wrapped one, and an answer in any other shape is a gap naming what the list holds" do
        text = ->(body) { { "content" => [ { "type" => "text", "text" => body.to_json } ] } }
        bare = Supabase.new { |tool, _arguments| tool == Supabase::LIST_PROJECTS ? text.(PROJECTS["projects"]) : text.(BRANCHES["branches"]) }.map
        assert_equal [ ResourceMap::KIND_DATABASE, ResourceMap::KIND_BRANCH, ResourceMap::KIND_BRANCH ], bare.resources.map(&:kind)
        assert_empty bare.gaps

        odd = Supabase.new { |tool, _arguments| tool == Supabase::LIST_PROJECTS ? text.({ "data" => [] }) : answer(tool) }.map
        assert_empty odd.resources
        assert_equal [ "Supabase answered the projects in a shape Firefight does not read." ], odd.gap_texts
        assert_equal [ ResourceMap::KIND_DATABASE, ResourceMap::KIND_BRANCH ], odd.unread_kinds

        branches = Supabase.new { |tool, _arguments| tool == Supabase::LIST_BRANCHES ? text.({ "message" => "ok" }) : answer(tool) }.map
        assert_equal [ ResourceMap::KIND_BRANCH ], branches.unread_kinds
      end

      test "a connection scoped to one project puts that project on the map by its ref, with its branches" do
        asked = []
        snapshot = Supabase.new(settings("project_ref" => "abcdefghijklmnopqrst")) do |tool, arguments|
          asked << [ tool, arguments ]
          answer(tool)
        end.map

        project, *branches = snapshot.resources
        assert_equal [ ResourceMap::KIND_DATABASE, "abcdefghijklmnopqrst", "abcdefghijklmnopqrst" ], [ project.kind, project.external_id, project.name ]
        assert_equal 2, branches.size
        assert_equal [ Supabase::LIST_BRANCHES ], asked.map(&:first)
        assert_match "scoped to project abcdefghijklmnopqrst", snapshot.gaps.sole.text
      end

      test "a project and each branch of its own are reached at their host, their dedicated pooler, the shared pooler by ref and the API address" do
        snapshot = Supabase.new(settings) { |tool, _arguments| answer(tool) }.map
        project, _main, feature = snapshot.resources
        workspace = workspaces(:slack_workspace_one)

        assert_equal [ project.key ] * 5 + [ feature.key ] * 5, snapshot.endpoints.map(&:resource)
        assert_includes snapshot.endpoints.map(&:fingerprint), ResourceMap::Fingerprint.of("db.abcdefghijklmnopqrst.supabase.co", 6543, workspace)
        assert_includes snapshot.endpoints.map(&:fingerprint), ResourceMap::Fingerprint.of("abcdefghijklmnopqrst.supabase.co", 443, workspace)
        pooled = snapshot.endpoints.select(&:within_domain)
        assert_equal [ 5432, 6543 ] * 2, pooled.map(&:port)
        assert_equal ResourceMap::Fingerprint.of_name("zyxwvutsrqponmlkjihg", workspace), pooled.last.tenant_fingerprint

        use = ResourceMap::Use.of(%w[web], "DATABASE_URL", "postgres://postgres.abcdefghijklmnopqrst:pw@aws-1-us-east-1.pooler.supabase.com:6543/postgres", workspace)
        assert pooled.any? { |endpoint| endpoint.fingerprint == use.domain_fingerprint && endpoint.tenant_fingerprint == use.tenant_fingerprint && endpoint.resource == project.key }
        assert_no_match(/supabase\.co/, snapshot.inspect.gsub(%r{https://supabase\.com/dashboard\S*}, ""))
      end

      test "a re-read of one project reads it and its branches as the sweep does, and finds it gone only when Supabase says not found" do
        tools = { Supabase::GET_PROJECT => Integration::Tool.new, Supabase::LIST_BRANCHES => Integration::Tool.new }
        scope = ResourceMap::Scope.new(account: "acme", kind: ResourceMap::KIND_DATABASE, external_id: "abcdefghijklmnopqrst")
        asked = []
        snapshot = Supabase.new(settings, tools) do |tool, arguments|
          asked << [ tool, arguments ]
          next answer(tool) unless tool == Supabase::GET_PROJECT

          { "content" => [ { "type" => "text", "text" => PROJECTS["projects"].first.merge("status" => "INACTIVE").to_json } ] }
        end.map(scope: scope)

        assert_equal [ Supabase::GET_PROJECT, { "id" => "abcdefghijklmnopqrst" } ], asked.first
        project = snapshot.resources.first
        assert_equal [ [ "supabase", "acme", ResourceMap::KIND_DATABASE, "abcdefghijklmnopqrst" ], "INACTIVE" ], [ project.key, project.status ]
        assert_equal 3, snapshot.resources.size

        missing = { "content" => [ { "type" => "text", "text" => "Project not found" } ], "isError" => true }
        gone = Supabase.new(settings, tools) { |tool, _arguments| tool == Supabase::GET_PROJECT ? missing : answer(tool) }.map(scope: scope)
        assert_equal [ [ "supabase", "acme", ResourceMap::KIND_DATABASE, "abcdefghijklmnopqrst" ] ], gone.gone

        refused = { "content" => [ { "type" => "text", "text" => "Your account does not have the necessary privileges" } ], "isError" => true }
        assert_raises(Integrations::Error) { Supabase.new(settings, tools) { |_tool, _arguments| refused }.map(scope: scope) }
        assert_nil Supabase.new(settings, {}) { |tool, _arguments| answer(tool) }.map(scope: scope), "with get_project off a sweep reads it"
      end

      test "a connection scoped to one project reads only that one again, and nothing for another project an organization's endpoint sent" do
        scoped = settings(Capabilities::Supabase::SCOPED_TO => "abcdefghijklmnopqrst")
        ours = Supabase.new(scoped) { |tool, _arguments| answer(tool) }
                       .map(scope: ResourceMap::Scope.new(account: "acme", kind: ResourceMap::KIND_DATABASE, external_id: "abcdefghijklmnopqrst"))
        assert_equal "abcdefghijklmnopqrst", ours.resources.first.external_id

        other = Supabase.new(scoped) { |tool, _arguments| answer(tool) }
                        .map(scope: ResourceMap::Scope.new(account: "acme", kind: ResourceMap::KIND_DATABASE, external_id: "anotherprojectrefxxx"))
        assert_equal [ [], [] ], [ other.resources, other.gone ]
      end

      private

      def settings(fields = {})
        integration = Integration.new(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_MCP, provider: Supabase::PROVIDER,
                                      settings: { Integration::FIELDS_SETTING => fields })
        ConnectionSettings.of(integration.integration_environments.build)
      end

      def answer(tool) = { "content" => [ { "type" => "text", "text" => { Supabase::LIST_PROJECTS => PROJECTS, Supabase::LIST_BRANCHES => BRANCHES }.fetch(tool).to_json } ] }
    end
  end
end

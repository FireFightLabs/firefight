require "test_helper"

# What the handbook syncs pages from, read through the integrations layer: a repository's text files through its code
# host, a document through its tool's own server, and the pushes that say a branch moved.
module Integrations
  class HandbookDocumentsTest < ActiveSupport::TestCase
    Entry = Packs::CodeHost::Infrastructure::Entry
    Listing = Packs::CodeHost::Infrastructure::Listing

    # A host's reader as CodeHost::Documents uses it.
    class FakeReader
      def initialize(entries, contents) = (@entries, @contents = entries, contents)
      def listing(_repository) = Listing.new(entries: @entries, truncated: false)
      def content(_repository, entry) = @contents.fetch(entry.path)
      def url(repository, path) = "https://code.example/#{repository['full_name']}/blob/main/#{path}"
    end

    REPOSITORY = { "full_name" => "acme/web", "default_branch" => "main" }.freeze

    setup do
      @workspace = workspaces(:slack_workspace_one)
    end

    test "a folder brings in its text files, never one that may hold secrets, and says what was too large" do
      entries = [ Entry.new(path: "docs/release.md", size: 20, id: nil), Entry.new(path: "docs/owners.txt", size: 20, id: nil),
                  Entry.new(path: "docs/diagram.png", size: 20, id: nil), Entry.new(path: "docs/.env.md", size: 20, id: nil),
                  Entry.new(path: "docs/huge.md", size: 300_000, id: nil), Entry.new(path: "src/app.rb", size: 20, id: nil) ]
      reader = FakeReader.new(entries, { "docs/release.md" => "# Release", "docs/owners.txt" => "Payments" })

      read = Packs::CodeHost::Documents.new(reader).read(REPOSITORY, "docs/")

      assert_equal %w[docs/owners.txt docs/release.md], read.files.map(&:path)
      assert_equal "https://code.example/acme/web/blob/main/docs/release.md", read.files.last.url
      assert_equal [ "docs/huge.md is over 200 KB and was not read." ], read.gaps
      assert_equal "main", read.branch
    end

    test "one file is read by its path, and a path with nothing there or one that may hold secrets is refused" do
      reader = FakeReader.new([ Entry.new(path: "AGENTS.md", size: 20, id: nil) ], { "AGENTS.md" => "Run make test." })

      assert_equal [ "Run make test." ], Packs::CodeHost::Documents.new(reader).read(REPOSITORY, "AGENTS.md").files.map(&:content)
      assert_raises(Integrations::Error) { Packs::CodeHost::Documents.new(reader).read(REPOSITORY, "HANDBOOK.md") }
      assert_raises(Integrations::Error) { Packs::CodeHost::Documents.new(reader).read(REPOSITORY, "config/credentials.md") }
    end

    test "a code host reads repositories and a document tool reads documents, each by its definition" do
      github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "Acme code")
      notion = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "notion", name: "Notion")
      grafana = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "grafana", name: "Grafana")

      assert RepositoryDocuments.reads?(github)
      assert_not RepositoryDocuments.reads?(notion)
      assert Documents.reads?(notion)
      assert_not Documents.reads?(grafana)
    end

    test "a Notion page is read through notion-fetch, keeping its body, title and address, recorded under the handbook sync" do
      notion = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "notion", name: "Notion", slug: "notion",
                                               settings: { "server_url" => "https://mcp.notion.com/mcp" })
      notion.integration_environments.create!(credentials: { authorization: "Bearer x" }.to_json)
      notion.tools.create!(name: "notion_fetch", description: "Fetch", read_only: true, enabled: true, params_schema: {}, spec: { "tool_name" => "notion-fetch" })
      answer = { "title" => "Release guide", "url" => "https://www.notion.so/Release-guide-1",
                 "text" => "<page url=\"https://www.notion.so/Release-guide-1\">\n<properties>{}</properties>\n<content>\n## Steps\n\nShip on Tuesdays.\n</content>\n</page>" }
      McpClient.any_instance.expects(:call_tool).with(name: "notion-fetch", arguments: { "id" => "https://www.notion.so/Release-guide-1" })
               .returns({ "content" => [ { "type" => "text", "text" => answer.to_json } ] })

      page = Documents.read(notion, "https://www.notion.so/Release-guide-1")

      assert_equal [ "Release guide", "## Steps\n\nShip on Tuesdays.", "https://www.notion.so/Release-guide-1" ], [ page.title, page.text, page.url ]
      logged = Ability::Invocation.find_by!(workspace: @workspace, source: AbilityGateway::SOURCE_HANDBOOK_SYNC)
      assert_equal SystemAgent.handbook_sync, logged.principal
    end

    def confluence_connection(tools)
      confluence = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "confluence", name: "Confluence", slug: "confluence",
                                                   settings: { "server_url" => "https://mcp.atlassian.com/v2/mcp?tools=all" })
      confluence.integration_environments.create!(credentials: { authorization: "Bearer x" }.to_json)
      tools.each do |name, remote|
        confluence.tools.create!(name: name, description: name, read_only: true, enabled: true, params_schema: {}, spec: { "tool_name" => remote })
      end
      confluence
    end

    test "a Confluence page is read by its link through getConfluenceContent as Markdown, keeping its body, title and address" do
      confluence = confluence_connection("getconfluencecontent" => "getConfluenceContent")
      answer = { "id" => "123456", "title" => "Checkout runbook", "body" => { "markdown" => "## Steps\n\nRestart checkout." },
                 "_links" => { "webui" => "/spaces/ENG/pages/123456/Checkout+runbook", "base" => "https://acme.atlassian.net/wiki" } }
      McpClient.any_instance.expects(:call_tool)
               .with(name: "getConfluenceContent", arguments: { "cloudId" => "acme.atlassian.net", "content_id" => "123456", "content_format" => "markdown" })
               .returns({ "content" => [ { "type" => "text", "text" => answer.to_json } ] })

      page = Documents.read(confluence, "https://acme.atlassian.net/wiki/spaces/ENG/pages/123456/Checkout+runbook")

      assert Documents.reads?(confluence)
      assert_equal [ "Checkout runbook", "## Steps\n\nRestart checkout.", "https://acme.atlassian.net/wiki/spaces/ENG/pages/123456/Checkout+runbook" ],
                   [ page.title, page.text, page.url ]
      assert_equal SystemAgent.handbook_sync, Ability::Invocation.find_by!(workspace: @workspace, source: AbilityGateway::SOURCE_HANDBOOK_SYNC).principal
    end

    test "a Confluence page named by its id alone is read on the one site the connection reaches, and kept whole when its shape is not known" do
      confluence = confluence_connection("getconfluencecontent" => "getConfluenceContent", "getaccessibleatlassianresources" => "getAccessibleAtlassianResources")
      sites = [ { "id" => "1324a887", "url" => "https://acme.atlassian.net", "name" => "acme" } ]
      McpClient.any_instance.expects(:call_tool).with(name: "getAccessibleAtlassianResources", arguments: {})
               .returns({ "content" => [ { "type" => "text", "text" => sites.to_json } ] })
      McpClient.any_instance.expects(:call_tool)
               .with(name: "getConfluenceContent", arguments: { "cloudId" => "acme.atlassian.net", "content_id" => "77", "content_format" => "markdown" })
               .returns({ "content" => [ { "type" => "text", "text" => "# Deploys\n\nShip on Tuesdays." } ] })

      page = Documents.read(confluence, "77")

      assert_equal [ "Confluence page", "# Deploys\n\nShip on Tuesdays.", "https://acme.atlassian.net/wiki/pages/viewpage.action?pageId=77" ],
                   [ page.title, page.text, page.url ]
    end

    test "a Confluence reference that names no page, or a page whose read is switched off, says so" do
      confluence = confluence_connection({})

      assert_match "Paste the Confluence page's link", assert_raises(Integrations::Error) { Documents.read(confluence, "the runbook") }.message
      assert_match "getConfluenceContent is switched off",
                   assert_raises(Integrations::Error) { Documents.read(confluence, "https://acme.atlassian.net/wiki/spaces/ENG/pages/1/Runbook") }.message
    end

    test "each code host says which branch a push moved" do
      github = MapEventSources::Github.branch_pushes({ "ref" => "refs/heads/main", "repository" => { "full_name" => "acme/web" } },
                                                    headers: { "x-github-event" => "push" })
      gitlab = MapEventSources::Gitlab.branch_pushes({ "ref" => "refs/heads/release", "project" => { "path_with_namespace" => "acme/platform/web" } },
                                                    headers: { "x-gitlab-event" => "Push Hook" })
      bitbucket = MapEventSources::Bitbucket.branch_pushes({ "repository" => { "full_name" => "acme/web" },
                                                             "push" => { "changes" => [ { "new" => { "type" => "branch", "name" => "main" } } ] } },
                                                           headers: { "x-event-key" => "repo:push" })

      assert_equal [ RepositoryDocuments::Push.new(repository: "acme/web", branch: "main") ], github
      assert_equal [ RepositoryDocuments::Push.new(repository: "acme/platform/web", branch: "release") ], gitlab
      assert_equal [ RepositoryDocuments::Push.new(repository: "acme/web", branch: "main") ], bitbucket
      assert_empty MapEventSources::Github.branch_pushes({ "ref" => "refs/heads/main", "deleted" => true, "repository" => { "full_name" => "acme/web" } },
                                                         headers: { "x-github-event" => "push" })
    end
  end
end

require "test_helper"

class Chat::Tools::DocsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @investigation = @workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400
    )
    store_doc_page(provider: "northflank", path: "docs/application/release/run-and-manage-workflows.md",
                   url: "https://northflank.com/docs/v1/application/release/run-and-manage-workflows.md", content: <<~MARKDOWN)
                     # Run and manage workflows

                     ## Run a workflow using a webhook

                     Treat the URL as a credential.

                     ### Git trigger parameters

                     Pass `<git-trigger>.sha` and `<git-trigger>.branch` as query parameters.

                     ## View runs

                     The state of the current run is in the header.
                   MARKDOWN
    store_doc_page(provider: "render", path: "deploy/hooks.md", content: "# Deploy hooks\n\nA deploy hook starts a deploy with its sha.")
    FirefightAi.stubs(:embed).raises(FirefightAi::TerminalError.new("no key", reason: "ConfigurationError"))
  end

  test "a run and a chat both hold search_docs and read_doc" do
    names = Investigation::Tools.for(@investigation, offer: ->(_tools) { }).map(&:name)

    assert_includes names, Chat::Tools::Docs::SEARCH
    assert_includes names, Chat::Tools::Docs::READ
    assert_equal Chat::Tools::KIND_READ, Chat::Tools.kind(Chat::Tools::Docs::SEARCH, @workspace)
  end

  test "a search answers the few best sections of the connected providers' documentation, as snippets with their page and address, framed as evidence" do
    connect("northflank")

    answer = tool(Chat::Tools::Docs::SEARCH).call("query" => "webhook sha query parameters")

    assert answer.start_with?(Chat::Tools::Docs::NOTE)
    assert_includes answer, %(<tool_result tool="search_docs" trust="untrusted">)
    assert_includes answer, "1. Northflank: Run and manage workflows > Run a workflow using a webhook > Git trigger parameters"
    assert_includes answer, "provider northflank, page docs/application/release/run-and-manage-workflows.md"
    assert_includes answer, "https://northflank.com/docs/v1/application/release/run-and-manage-workflows.md"
    assert_not_includes answer, "Deploy hooks", "Render is not connected"
  end

  test "a provider named in the search is searched whether or not it is connected" do
    answer = tool(Chat::Tools::Docs::SEARCH).call("query" => "deploy hook sha", "provider" => "Render")

    assert_includes answer, "Render: Deploy hooks"
  end

  test "documentation never read says so plainly, so Halon works from its skills and tells the person" do
    connect("planetscale")

    assert_includes tool(Chat::Tools::Docs::SEARCH).call("query" => "connections"), "is not available in this Firefight yet"
    assert_includes tool(Chat::Tools::Docs::READ).call("provider" => "planetscale", "page" => "postgres/x.md"),
                    "tell the person the documentation was not available"
  end

  test "read_doc returns one section and those under it, with where it came from" do
    answer = tool(Chat::Tools::Docs::READ).call("provider" => "northflank", "page" => "docs/application/release/run-and-manage-workflows.md",
                                                "section" => "Run a workflow using a webhook")

    assert_includes answer, "Source: Run and manage workflows, https://northflank.com/docs/v1/application/release/run-and-manage-workflows.md"
    assert_includes answer, "Treat the URL as a credential."
    assert_includes answer, "<git-trigger>.sha"
    assert_not_includes answer, "The state of the current run"
    assert_equal "https://northflank.com/docs/v1/application/release/run-and-manage-workflows.md", Integrations::SourceLinks.cited_in(answer.delete_suffix("\n</tool_result>")).url
  end

  test "a long page is offered by its sections rather than whole, and a missing page or section says what there is" do
    long = "# Huge\n\n## First\n\n#{'word ' * 3_000}\n\n## Second\n\n#{'word ' * 3_000}"
    store_doc_page(provider: "northflank", path: "docs/huge.md", content: long)

    assert_includes tool(Chat::Tools::Docs::READ).call("provider" => "northflank", "page" => "docs/huge.md"), "is long, so read it a section at a time"
    assert_includes tool(Chat::Tools::Docs::READ).call("provider" => "northflank", "page" => "docs/huge.md", "section" => "Third"), "Its sections are: First; Second."
    assert_includes tool(Chat::Tools::Docs::READ).call("provider" => "northflank", "page" => "docs/nope.md"), "has no page docs/nope.md"
  end

  private

  def tool(kind) = Chat::Tools::Docs.new(@investigation, kind)

  def connect(provider) = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: provider, name: provider.humanize)
end

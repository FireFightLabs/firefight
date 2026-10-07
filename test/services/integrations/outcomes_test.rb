require "test_helper"

module Integrations
  class OutcomesTest < ActiveSupport::TestCase
    NotThere = Class.new(Integrations::Error) { include Integrations::NotFound }
    CLOUDFLARE_NOT_FOUND = "Error: Cloudflare API error: 8000007: Project not found.".freeze

    setup do
      workspace = workspaces(:slack_workspace_one)
      @fake = workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "fake", name: "Fake")
      @reads = @fake.tools.create!(name: "echo_text", description: "Echoes", params_schema: {}, enabled: true, read_only: true)
      @writes = @fake.tools.create!(name: "write_thing", description: "Writes", params_schema: {}, enabled: true, read_only: false)
      cloudflare = workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "cloudflare", name: "Cloudflare", slug: "cloudflare",
                                                  settings: { "server_url" => "https://mcp.cloudflare.com/mcp" })
      @execute = cloudflare.tools.create!(name: "execute", description: "Call the API", params_schema: {}, enabled: true, read_only: false)
    end

    test "a read the provider answered not found is a not found, and a change it answered the same is a failure" do
      assert Outcomes.not_found?(@reads, {}, error: NotThere.new("Fake answered 404: no such thing"))
      assert_not Outcomes.not_found?(@writes, {}, error: NotThere.new("Fake answered 404: no such thing"))
      assert_not Outcomes.not_found?(@reads, {}, error: Integrations::Error.new("Fake answered 500: broken"))
    end

    test "a remote server's own answer is read by its provider's error reader, and only for a call shown to read" do
      get = { "code" => "async () => cloudflare.request({method:'GET', path:'/accounts/a/pages/projects/ember'})" }
      delete = { "code" => "async () => cloudflare.request({method:'DELETE', path:'/accounts/a/pages/projects/ember'})" }

      assert Outcomes.not_found?(@execute, get, said: CLOUDFLARE_NOT_FOUND)
      assert_not Outcomes.not_found?(@execute, delete, said: CLOUDFLARE_NOT_FOUND)
      assert_not Outcomes.not_found?(@execute, get, said: "Error: Cloudflare API error: 10000: Authentication error")
      assert_not Outcomes.not_found?(@reads, {}, said: "Project not found"), "a provider with no error reader never reads as not found"
    end
  end
end

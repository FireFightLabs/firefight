require "test_helper"

module Integrations
  class ApiIndexTest < ActiveSupport::TestCase
    # Each provider whose general read guesses paths keeps an index of its key reads.
    PROVIDERS = %w[
      aws azure azure_devops bitbucket cloudflare digitalocean fly github gitlab google_cloud kubernetes netlify northflank railway render
      tinybird trigger_dev vercel
    ].freeze
    SAMPLE = "sample1".freeze
    # What an index may add to its skill, in tokens (FirefightAi::TOOL_CHARS_PER_TOKEN), so loading it stays cheap.
    TOKEN_CAP = 1_600

    test "every provider with a general read keeps an index of at most forty reads, each with a purpose" do
      assert_equal PROVIDERS, ApiIndex.all.map(&:provider)

      ApiIndex.all.each do |index|
        assert index.reads.size.between?(10, ApiIndex::LIMIT), "#{index.provider} lists #{index.reads.size} reads"
        assert index.reference.present? ^ index.source.present?, "#{index.provider} names a docs store reference or the address it was taken from"
        assert_equal index.reads.size, index.reads.map { |read| [ read.service, read.call ] }.uniq.size, "#{index.provider} lists a read twice"
        index.reads.each do |read|
          assert read.purpose.match?(/\A[A-Z0-9].*\.\z/), "#{index.provider} #{read.call} has a purpose written as a sentence"
          assert_no_match(/[—;]/, read.purpose, "#{index.provider} #{read.call}")
        end
      end
    end

    test "an index lists only reads, never a call that writes" do
      ApiIndex.all.each do |index|
        index.reads.each do |read|
          case index.shape
          when ApiIndex::SHAPE_OPERATION then assert ReadGuards::Aws.read?(read.service, read.call), "#{index.provider} #{read.call}"
          when ApiIndex::SHAPE_GRAPHQL then assert read.call.start_with?("query "), "#{index.provider} #{read.call}"
          else assert_equal ApiIndex::GET, read.verb, "#{index.provider} #{read.call}"
          end
        end
      end
    end

    test "every read an index names is one its provider's read guard lets through" do
      ApiIndex.all.each do |index|
        guard = Provider.for(index.provider).read_guard
        assert guard&.guards?(index.tool), "#{index.provider}'s read guard guards #{index.tool}"

        index.reads.each do |read|
          arguments = arguments_for(index, read)
          refused = begin
            reading = guard.reading(index.tool, arguments)
            guard.respond_to?(:withheld) ? guard.withheld(index.tool, reading) : nil
          rescue ReadGuards::Refused, PolicyRefusal => error
            error.message
          end
          assert_nil refused, "#{index.provider} #{read.call} is refused by its read guard"
          assert ReadGuards.read_call?(tool_for(index), arguments), "#{index.provider} #{read.call} reads"
        end
      end
    end

    test "an index's tool is its provider's general read" do
      ApiIndex.all.each do |index|
        pack = Provider.for(index.provider).pack
        next assert(Provider.for(index.provider).read_guard.guards?(index.tool)) unless pack

        assert_includes pack.tool_definitions.map(&:name), index.tool, index.provider
      end
    end

    test "each index closes its provider's API skill as it is written now, within the token cap" do
      ApiIndex.all.each do |index|
        skill = Chat::Skill.find(index.skill)
        assert skill, "#{index.provider}'s index closes the #{index.skill} skill"
        assert_equal index.provider, skill.source
        assert skill.tools.include?(index.tool), "#{index.skill} names #{index.tool}"
        assert skill.steps.end_with?(index.text), "#{index.skill} ends with #{index.provider}'s index as it is now. Run bin/rails provider_docs:api_indexes"
        assert_equal 1, skill.steps.scan(ApiIndex::HEADING).size
        tokens = (index.text.size / FirefightAi::TOOL_CHARS_PER_TOKEN).ceil
        assert tokens <= TOKEN_CAP, "#{index.provider}'s index is #{tokens} tokens"
      end
    end

    test "an index file is written as the refresh writes it, so a hand edit never drifts from its form" do
      ApiIndex.all.each do |index|
        assert_equal ApiIndex::Refresh.yaml(index, index.reads), File.read(ApiIndex::DIRECTORY.join("#{index.provider}.yml")), index.provider
      end
    end

    test "a path the index holds gets no hint, since its failure is about what the path names" do
      assert_nil ApiIndex.hint("github", "api_read", "path" => "/repos/acme/shop/actions/workflows/deploy.yml/runs")
      assert_nil ApiIndex.hint("github", "list_repositories", "path" => "/nowhere")
      assert_nil ApiIndex.hint("notion", "api_read", "path" => "/nowhere")
    end

    test "a path the index does not hold is answered with the nearest key reads" do
      hint = ApiIndex.hint("github", "api_read", "path" => "/repos/acme/shop/actions/workflow/deploy.yml/runs")

      assert_includes hint, "GET /repos/acme/shop/actions/workflow/deploy.yml/runs is not among the key reads Firefight keeps for GitHub"
      assert_includes hint, "GET /repos/{owner}/{repo}/actions/workflows/{workflow_id}/runs"
      assert_includes hint, "The github_api skill lists every key read"
    end

    test "a wrong guess at an audit log finds the provider's audit reads" do
      index = ApiIndex.for("github")
      nearest = index.nearest(index.asked("path" => "/repos/acme/shop/audit-log")).map(&:call)

      assert_includes nearest, "GET /repos/{owner}/{repo}/activity"
    end

    test "a change through a general tool that also changes gets no hint, since the index lists reads" do
      assert_nil ApiIndex.hint("northflank", "api_request", "method" => "POST", "path" => "workflows/release/runs-start")
    end

    test "an AWS operation the index does not hold is answered with the nearest operations" do
      hint = ApiIndex.hint("aws", "api_read", "service" => "ecs", "operation" => "ListService")

      assert_includes hint, "ecs ListService is not among the key reads"
      assert_includes hint, "ecs: ListServices"
    end

    test "a failure Firefight's own rule gave or a rate limit is left as it is" do
      arguments = { "path" => "/repos/acme/shop/nowhere" }

      assert_nil ApiIndex.hint_after(PolicyRefusal.new("no"), "github", "api_read", arguments)
      assert ApiIndex.hint_after(Integrations::Error.new("GitHub found nothing"), "github", "api_read", arguments)
    end

    test "a general read that fails on a path the index does not hold says the nearest ones" do
      integration = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github_hint", settings: {})
      pack = NativePack.fetch!(integration)
      pack.stubs(:api_read).raises(NativePack::Error, "GitHub found nothing at /repos/acme/shop/audit")
      error = assert_raises(NativePack::Error) { pack.call("api_read", environment_row: nil, arguments: { "path" => "/repos/acme/shop/audit" }) }

      assert error.message.start_with?("GitHub found nothing at /repos/acme/shop/audit. GET /repos/acme/shop/audit is not among the key reads")
    end

    test "a remote server's failed answer carries the hint, and a good one is left alone" do
      failed = { "content" => [ { "type" => "text", "text" => "Cloudflare API error: 7000: No route for that URI" } ], "isError" => true }
      code = "async () => cloudflare.request(#{JSON.generate('method' => 'GET', 'path' => '/zones/abc/audit')})"

      hinted = ApiIndex.hinted(failed, "cloudflare", "execute", { "code" => code }, failed: true)
      assert_equal 2, hinted["content"].size
      assert_includes hinted["content"].last["text"], "GET /zones/abc/audit is not among the key reads Firefight keeps for Cloudflare"
      assert_equal failed, ApiIndex.hinted(failed, "cloudflare", "execute", { "code" => code }, failed: false)
    end

    test "the refresh fills each read's query parameters from the reference and names a read it no longer lists" do
      source = ProviderDocSource.create!(key: "github_api", provider: "github", fetched_at: Time.current)
      page!(source, "api/actions.md", <<~MD)
        # actions

        ## GET /repos/{owner}/{repo}/actions/runs

        List workflow runs for a repository

        Path:
        - owner (string, required): The account owner.

        Query:
        - actor (string): Returns someone's workflow runs.
        - branch (string): Returns runs on a branch.
        - status (string, one of completed, failure): Returns runs with a status.
        - per_page (integer): The number of results per page.
        - created (string): Returns runs created in a range.

        Answers: total_count (integer)
      MD
      index = ApiIndex.new("github", "tool" => "api_read", "skill" => "github_api", "reference" => "api", "reads" => [
        { "call" => "GET /repos/{owner}/{repo}/actions/runs", "purpose" => "Workflow runs." },
        { "call" => "GET /repos/{owner}/{repo}/actions/runs", "service" => nil, "purpose" => "Runs again.", "query" => %w[actor gone] },
        { "call" => "GET /repos/{owner}/{repo}/actions/gone", "purpose" => "Gone." }
      ])

      result = ApiIndex::Refresh.new(index).run(write: false)

      assert_equal [ "GET /repos/{owner}/{repo}/actions/gone" ], result.stale
      assert_equal [ "GET /repos/{owner}/{repo}/actions/runs gone" ], result.dropped
      assert result.stale?
    end

    test "the refresh takes a fixed value a required parameter has, such as Azure's api-version" do
      source = ProviderDocSource.create!(key: "azure_api_web", provider: "azure", fetched_at: Time.current)
      page!(source, "api/web/sites.md", <<~MD)
        # Sites

        ## GET /subscriptions/{subscriptionId}/providers/Microsoft.Web/sites

        WebApps_List

        Query:
        - includeSlots (boolean): Whether to include slots.
        - api-version (string, one of 2026-07-15, required)
      MD
      read = ApiIndex::Read.new(call: "GET /subscriptions/{subscriptionId}/providers/Microsoft.Web/sites", service: "web", purpose: "Web Apps.", query: [ "api-version=2024-01-01" ])
      index = ApiIndex.new("azure", "tool" => "api_read", "skill" => "azure_api", "reference" => "api", "reads" => [ read.to_h.stringify_keys ])

      refreshed = ApiIndex::Refresh.new(index).send(:refreshed, read, [], [])

      assert_equal [ "api-version=2026-07-15" ], refreshed.query
      assert_equal [ "api-version=2026-07-15" ], ApiIndex::Refresh.new(index).send(:refreshed, read.with(query: []), [], []).query
    end

    private

    def page!(source, path, content)
      ProviderDocPage.create!(source: source, provider: source.provider, path: path, url: "https://example.com/#{path}", title: path, fetched_at: Time.current,
                              content: content, content_digest: ProviderDocPage.digest_for(content))
    end

    def tool_for(index)
      Integration::Tool.new(name: index.tool, read_only: false, integration: Integration.new(provider: index.provider))
    end

    # A call to the read, with every placeholder filled, as a chat would make it.
    def arguments_for(index, read)
      case index.shape
      when ApiIndex::SHAPE_OPERATION
        { "service" => read.service, "operation" => read.call }
      when ApiIndex::SHAPE_GRAPHQL
        { "query" => "{ #{read.call.delete_prefix('query ')} { __typename } }" }
      else
        query = read.query.select { |name| name.include?("=") }.to_h { |pair| pair.split("=", 2) }
        arguments = { "method" => ApiIndex::GET, "path" => read.path.gsub(ApiIndex::PLACEHOLDER, SAMPLE), "query" => query }
        read.service ? arguments.merge("service" => read.service) : arguments
      end
    end
  end
end

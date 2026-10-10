require "test_helper"

module Integrations
  class ProviderTest < ActiveSupport::TestCase
    test "every provider definition is for a provider in the registry, at the file its key names, and every part it names loads" do
      definitions = Dir[Rails.root.join("app/services/integrations/providers/*.rb")].map { |path| File.basename(path, ".rb") }
      keys = IntegrationProvider.all.map(&:key)

      definitions.each do |file|
        definition = Provider.for(file)
        assert_equal file, definition.key, "providers/#{file}.rb defines #{definition.key}"
        assert_includes keys, definition.key, "#{file} has a definition and no registry entry"
        definition.part_names.each do |part, name|
          assert name.safe_constantize, "#{file} names #{name} as its #{part}, which does not load"
        end
      end
    end

    test "a provider with no code of its own has no parts, and a part a provider cannot have is refused" do
      confluence = Provider.for("confluence")

      assert_equal "confluence", confluence.key
      assert Provider::PARTS.all? { |part| confluence.public_send(part).nil? }
      assert_empty confluence.redacted_fields
      assert_nil Provider.for("../datadog").adapter
      assert_raises(ArgumentError) { Provider.new(key: "acme", poller: "Acme::Poller") }
    end

    test "a provider's map events source loads and answers the contract its definition promises" do
      definitions = Provider.all + [ Provider.for("livetest"), Provider.for("livepoll"), Provider.for("livehook"), Provider.for("liveapp") ]

      definitions.filter_map(&:map_events).each do |source|
        assert_operator source, :<, MapEventSource, "#{source} is a MapEventSource"
        %i[verify events setup_steps].each { |method| assert source.respond_to?(method), "#{source} answers #{method}" }
        assert source.respond_to?(:refresh) == false || source.registers?, "#{source} refreshes a webhook it never registers"
        assert source.respond_to?(:remove) == source.registers?, "#{source} registers a webhook it cannot take back" if source.registers?
        assert source.setup_steps.any?, "#{source} is neither registered, polled nor app wide, so an admin needs its steps" unless source.registers? || source.polls? || source.app_wide?
      end
    end

    test "a provider's command line tool names its command and the tool it runs as, and points at Firefight with a token, never a key" do
      Provider.all.filter_map(&:cli).each do |cli|
        assert cli::COMMAND.present? && cli::TOOL.present?, "#{cli} names its command and tool"
        assert_equal [ "https://ff.example/x", "tok" ].sort, cli.env("https://ff.example/x", "tok").values.sort, "#{cli} is handed only the relay and the token"
        %i[arguments answer].each { |method| assert cli.respond_to?(method), "#{cli} answers #{method}" }
      end
    end

    test "Northflank's command line tool reaches what is inside a project and nothing else" do
      cli = Provider.for("northflank").cli

      assert_equal({ "method" => "POST", "path" => "services/web/restart", "project" => "shop", "body" => { "a" => 1 } },
                   cli.arguments("post", "/v1/projects/shop/services/web/restart", {}, { "a" => 1 }))
      [ "v1/projects", "v1/teams/t/projects/shop/services", "v1/projects/shop", "v1/projects/../x/services" ].each do |path|
        assert_raises(Clis::Refused, path) { cli.arguments("GET", path, {}, nil) }
      end
    end

    test "every status word a provider maps is one of Firefight's own" do
      firefight = ResourceMap::Resource::STATUS_HEALTH.keys
      assert_includes firefight, "stopped", "Firefight's own status words are what providers map onto"
      Provider.all.each do |definition|
        definition.status_words.each_value do |word|
          assert_includes firefight, word, "#{definition.key} maps a status onto #{word}, which is not one of Firefight's words"
        end
      end
    end

    test "a provider's status words are put in Firefight's words when its connection is swept" do
      definition = Provider.new(key: "acme", status_words: { "Current" => "ready", "scaled down" => "stopped" })
      found = ->(status) { ResourceMap::Found.new(provider: "acme", account: "a", kind: ResourceMap::KIND_SERVICE, external_id: status.to_s, name: status.to_s, status: status) }
      snapshot = ResourceMap::Snapshot.new(resources: [ found.("current"), found.("Scaled down"), found.("odd"), found.(nil) ])

      assert_equal [ "ready", "stopped", "odd", nil ], definition.in_firefight_words(snapshot).resources.map(&:status)
    end

    test "Cloudflare's and Northflank's in-between states read a known health" do
      health = ->(key, word) { ResourceMap::Resource.new(status: Provider.for(key).status_of(word)).health }

      assert_equal %w[busy failing busy busy], %w[initializing moved inactive disabled].map { |word| health.("cloudflare", word) }
      assert_equal [ ResourceMap::Resource::HEALTH_BUSY ] * 6 + [ ResourceMap::Resource::HEALTH_FAILING ],
                   %w[preDeployment allocating scaling upgrading backup deleting errorAllocating].map { |word| health.("northflank", word) }
    end

    test "the registry's promises are kept by the definitions" do
      IntegrationProvider.all.each do |entry|
        definition = Provider.for(entry.key)
        assert definition.pack, "#{entry.key} is kind: native and has no pack" if entry.kind == Integration::KIND_NATIVE
        if entry.kind == Integration::KIND_MCP && entry.source_links == IntegrationProvider::SOURCE_LINKS_FIREFIGHT
          assert definition.source_links, "#{entry.key} says Firefight links its results and names no builder"
        end
        answers_history = definition.adapter&.capabilities.to_a.include?(Capabilities::HISTORY)
        if entry.history == IntegrationProvider::HISTORY_FIREFIGHT
          assert answers_history, "#{entry.key} says Halon reads its run history and its adapter does not answer #{Capabilities::HISTORY}"
        else
          refute answers_history, "#{entry.key} answers #{Capabilities::HISTORY} and says history none"
          assert entry.history_note.present?, "#{entry.key} says history none without a history_note saying why"
        end
      end
    end

    test "every provider whose pack reads code is a code host, so its connections keep the paths Halon may not change" do
      reads_code = IntegrationProvider.all.select { |entry| Provider.for(entry.key).pack&.include?(Packs::CodeHost::Code) }.map(&:key)

      assert_equal %w[bitbucket github gitlab], reads_code.sort
      assert_equal reads_code.sort, IntegrationProvider.all.select(&:holds_code).map(&:key).sort
    end

    test "a provider whose stores settings are named for is on the map, and its words are whole words in capitals" do
      IntegrationProvider.all.select { |entry| entry.setting_words.any? }.each do |entry|
        assert_equal IntegrationProvider::MAP_FIREFIGHT, entry.map, "#{entry.key} names setting words for stores that are not on the map"
        entry.setting_words.each { |word| assert_match(/\A[A-Z][A-Z0-9]+\z/, word, "#{entry.key}'s setting word #{word}") }
      end
      assert_includes ResourceMap::Use.words("NEON_DATABASE_URL"), IntegrationProvider.find("neon").setting_words.first
    end

    # The rest of the app reaches a provider through the shared contracts, so code outside the integrations layer never
    # decides by which provider it is. ArchSpec holds the constants, this holds the names. It looks for a provider's key
    # where a provider is compared or chosen (provider == "x", provider: "x", find("x"), for("x"), when "x"), so a key
    # that is also a common word, such as modal, collides with nothing. Alert sources keep their own list of providers,
    # which is not this one.
    test "nothing outside the integrations layer decides by which provider it is" do
      keys = (IntegrationProvider.all.map(&:key) - [ Integration::PROVIDER_CUSTOM_MCP ]).map { |key| Regexp.escape(key) }.join("|")
      allowed = %w[app/services/integrations/ app/adapters/integrations/ app/adapters/alert_providers app/models/alert_source.rb
                   app/frontend/lib/generated/ app/frontend/pages/settings/lib/alerts.ts]
      ruby = /(?:\bprovider\w*\s*(?:[!=]=|:)|\.(?:find|for|adapter_for|provider_tool|halon_sentence)\(|\bwhen)\s*["'](?:#{keys})["']/
      typescript = /(?:\bprovider\w*|\bkey)\s*(?:[!=]==?|:)\s*["'](?:#{keys})["']|\bcase\s+["'](?:#{keys})["']/

      named = Dir[Rails.root.join("{app,lib}/**/*.{rb,ts,tsx}")].flat_map do |path|
        relative = Pathname(path).relative_path_from(Rails.root).to_s
        next [] if allowed.any? { |prefix| relative.start_with?(prefix) }

        pattern = relative.end_with?(".rb") ? ruby : typescript
        File.readlines(path).each_with_index.filter_map { |line, index| "#{relative}:#{index + 1}" if line.match?(pattern) && !line.strip.start_with?("#", "//") }
      end

      assert_empty named, "These decide by which provider it is outside the integrations layer. Ask the integrations layer instead."
    end

    test "a provider's key is found where a provider is chosen, and a common word that happens to be one is not" do
      ruby = /(?:\bprovider\w*\s*(?:[!=]=|:)|\.(?:find|for)\(|\bwhen)\s*["'](?:modal)["']/

      assert_match ruby, 'next if integration.provider == "modal"'
      assert_match ruby, 'IntegrationProvider.find("modal")'
      assert_no_match ruby, 'adapter.open_modal(type: "modal", view: view)'
    end
  end
end

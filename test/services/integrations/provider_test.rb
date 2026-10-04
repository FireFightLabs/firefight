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
      linear = Provider.for("linear")

      assert_equal "linear", linear.key
      assert Provider::PARTS.all? { |part| linear.public_send(part).nil? }
      assert_empty linear.redacted_fields
      assert_nil Provider.for("../datadog").adapter
      assert_raises(ArgumentError) { Provider.new(key: "acme", poller: "Acme::Poller") }
    end

    test "the registry's promises are kept by the definitions" do
      IntegrationProvider.all.each do |entry|
        definition = Provider.for(entry.key)
        assert definition.pack, "#{entry.key} is kind: native and has no pack" if entry.kind == Integration::KIND_NATIVE
        if entry.kind == Integration::KIND_MCP && entry.source_links == IntegrationProvider::SOURCE_LINKS_FIREFIGHT
          assert definition.source_links, "#{entry.key} says Firefight links its results and names no builder"
        end
      end
    end

    # The rest of the app reaches a provider through the shared contracts, so a provider's key never appears as a
    # literal outside the integrations layer. ArchSpec holds its constants, this holds its name. Alert sources keep their
    # own list of providers, which is not this one.
    test "nothing outside the integrations layer names a provider" do
      keys = IntegrationProvider.all.map(&:key) - [ Integration::PROVIDER_CUSTOM_MCP ]
      allowed = %w[app/services/integrations/ app/adapters/integrations/ app/adapters/alert_providers app/models/alert_source.rb
                   app/frontend/lib/generated/ app/frontend/pages/settings/lib/alerts.ts]
      ruby = /["'](#{keys.join('|')})["']/
      typescript = /(?:===?|!==?|case)\s*["'](#{keys.join('|')})["']/

      named = Dir[Rails.root.join("{app,lib}/**/*.{rb,ts,tsx}")].filter_map do |path|
        relative = Pathname(path).relative_path_from(Rails.root).to_s
        next if allowed.any? { |prefix| relative.start_with?(prefix) }

        pattern = relative.end_with?(".rb") ? ruby : typescript
        lines = File.readlines(path).each_with_index.filter_map { |line, index| "#{relative}:#{index + 1}" if line.match?(pattern) && !line.strip.start_with?("#", "//") }
        lines.presence
      end.flatten

      assert_empty named, "These name a provider outside the integrations layer. Ask the integrations layer instead."
    end
  end
end

require "test_helper"

# Holds config/provider_docs.yml to what the docs store reads, so the daily refresh never fails on a source written
# wrong, and every page a skill lists is one a source can hold.
class ProviderDocSource::DefinitionTest < ActiveSupport::TestCase
  Definition = ProviderDocSource::Definition

  test "every source is one kind, with what that kind needs and nothing the refresh does not read" do
    raw = YAML.safe_load_file(Definition.path)
    Definition.all.each do |source|
      assert_equal 1, (Definition::KINDS.keys & raw.fetch(source.key).keys).size, "#{source.key} is one of #{Definition::KINDS.keys.join(', ')}"
      Definition::KINDS.fetch(source.kind).each { |key| assert source[key].present?, "#{source.key} names its #{key}" }
      allowed = [ source.kind ] + Definition::KINDS.fetch(source.kind) + Definition::OPTIONAL.fetch(source.kind) + Definition::SHARED
      assert_empty source.settings.keys - allowed, "#{source.key} names something the refresh does not read"
    end
  end

  test "every source belongs to a provider Firefight has and is read over https" do
    Definition.all.each do |source|
      assert IntegrationProvider.find(source.provider), "#{source.key} names #{source.provider}, which is not a provider"
      address = source.kind == Definition::KIND_PACKAGE ? "https://registry.npmjs.org/#{source.address}" : source.address
      assert address.start_with?("https://"), "#{source.key} is read over https"
      assert source.repository, "#{source.key} is a GitHub repository" if source.kind == Definition::KIND_REPOSITORY
    end
  end

  test "an index names the address its pages are under, and a site names each page as markdown" do
    Definition.all.select { |source| source.kind == Definition::KIND_INDEX }.each do |source|
      assert source["under"].start_with?("https://"), "#{source.key} reads pages over https"
      assert URI.parse(source.address).host == URI.parse(source["under"]).host, "#{source.key} reads pages from the site that lists them"
    end
    Definition.all.select { |source| source.kind == Definition::KIND_SITE }.each do |source|
      source.fetch("pages").each_key { |path| assert path.end_with?(".md"), "#{source.key} names #{path} as markdown" }
      assert source.page_url("x").start_with?(source.address), "#{source.key} reads pages from its own site"
    end
  end

  test "two sources of one provider never name the same page" do
    Definition.all.group_by(&:provider).each do |provider, sources|
      next if sources.one?

      sources.combination(2).each do |first, second|
        first.roots.product(second.roots).each do |one, other|
          assert_not one.start_with?(other) || other.start_with?(one), "#{provider}'s #{first.key} and #{second.key} both name pages under #{[ one, other ].min_by(&:length)}"
        end
      end
    end
  end

  test "Northflank's API is written out from its client, its product documentation is read from its index, and its own skill from its repository" do
    northflank = Definition.of("northflank").index_by(&:kind)

    assert_equal "@northflank/js-client", northflank.fetch(Definition::KIND_PACKAGE).address
    assert Rails.root.join("script/provider_docs/api_client_endpoints.mjs").exist?
    assert_equal "https://northflank.com/docs/llms.txt", northflank.fetch(Definition::KIND_INDEX).address
    assert northflank.fetch(Definition::KIND_INDEX).could_hold?("docs/application/release/run-and-manage-workflows.md")
    assert_equal "northflank/skills", northflank.fetch(Definition::KIND_REPOSITORY).repository
  end

  test "a page outside what a source names, or one that climbs out of it, is never one it could hold" do
    cloudflare = Definition.find("cloudflare")

    assert cloudflare.could_hold?("rules/operators.md")
    assert_not cloudflare.could_hold?("rules/not-listed.md")
    assert_not Definition.find("planetscale").could_hold?("postgres/../../master.key")
    assert_not Definition.find("planetscale").could_hold?("postgres/nested/deeper.md")
  end
end

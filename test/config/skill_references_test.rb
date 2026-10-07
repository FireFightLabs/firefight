require "test_helper"

# Holds config/skill_references.yml to what bin/sync-skill-references reads, so the daily copy never fails on a source
# written wrong, and every provider's guides are kept with their license and where they came from.
class SkillReferencesTest < ActiveSupport::TestCase
  KINDS = {
    "repository" => %w[license paths],
    "site" => %w[license pages],
    "package" => %w[license endpoints relative_to]
  }.freeze
  OPTIONAL = %w[notice extensions exclude page_url leave_out].freeze

  test "every source is one kind, with what that kind needs and nothing the sync does not read" do
    sources.each do |provider, source|
      kinds = KINDS.keys & source.keys
      assert_equal 1, kinds.size, "#{provider} is a repository, a site or a package"

      required = KINDS.fetch(kinds.first)
      required.each { |key| assert source[key].present?, "#{provider} names its #{key}" }
      assert_empty source.keys - kinds - required - OPTIONAL, "#{provider} names something the sync does not read"
    end
  end

  test "every source is a provider Firefight has, whose guides are kept with their license and origin" do
    sources.each_key do |provider|
      assert IntegrationProvider.find(provider), "#{provider} is not a provider"
      folder = Chat::Skill::DIRECTORY.join(provider, Chat::Skill::REFERENCES)
      assert folder.join("LICENSE").exist?, "#{provider} keeps no LICENSE"
      assert folder.join("SOURCE").exist?, "#{provider} does not say where its guides came from"
    end
  end

  test "a package's endpoints are written out by the script the sync runs, into an index that names every area" do
    packages = sources.select { |_provider, source| source["package"] }

    assert_includes packages.keys, "northflank"
    assert Rails.root.join("script/skill_references/api_client_endpoints.mjs").exist?
    packages.each do |provider, source|
      index = Chat::Skill.reference(provider, "#{source.fetch('endpoints')}/index.md")
      assert index, "#{provider} has no endpoint index"
      areas = index.scan(/^### \S+ \((\S+)\)$/).flatten
      assert areas.any?, "#{provider}'s index names no areas"
      areas.each { |area| assert Chat::Skill.reference(provider, "#{source.fetch('endpoints')}/#{area}"), "#{provider} keeps no #{area}" }
      assert_match source.fetch("package"), Chat::Skill::DIRECTORY.join(provider, Chat::Skill::REFERENCES, "SOURCE").read
    end
  end

  private

  def sources = YAML.safe_load_file(Rails.root.join("config/skill_references.yml"))
end

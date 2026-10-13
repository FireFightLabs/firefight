require "test_helper"

class FirefightLibraryTest < ActiveSupport::TestCase
  test "every library item has a version for what it says now" do
    assert FirefightLibrary.current?,
           "#{FirefightLibrary.stale.map { |kind, names| "#{kind}: #{names.join(', ')}" }.join('; ')} changed without a new version, run bin/rails library:versions"
  end

  test "an item whose words changed gets its next version, a new one version 1, and one that is gone is dropped" do
    Dir.mktmpdir do |dir|
      path = Pathname(dir).join("library_versions.yml")
      File.write(path, { "skills" => { "kept" => { "version" => 2, "digest" => "a" }, "changed" => { "version" => 4, "digest" => "b" },
                                       "gone" => { "version" => 1, "digest" => "c" } } }.to_yaml)
      stub_const(FirefightLibrary, :FILE, path) do
        FirefightLibrary.stubs(:sources).returns(FirefightLibrary::KIND_SKILLS => -> { { "kept" => "a", "changed" => "z", "new" => "n" } })
        FirefightLibrary.reset!

        assert_equal({ FirefightLibrary::KIND_SKILLS => %w[changed gone new] }, FirefightLibrary.stale)
        FirefightLibrary.write!

        assert_equal [ 2, 5, 1 ], %w[kept changed new].map { |name| FirefightLibrary.version(FirefightLibrary::KIND_SKILLS, name) }
        assert_nil FirefightLibrary.recorded(FirefightLibrary::KIND_SKILLS)["gone"]
        assert FirefightLibrary.current?
      end
    ensure
      FirefightLibrary.reset!
    end
  end

  test "each of Firefight's skills carries its library version" do
    skill = Chat::Skill.find("disk_trends")

    assert_equal FirefightLibrary.version(FirefightLibrary::KIND_SKILLS, "disk_trends"), skill.version
  end

  private

  def stub_const(owner, name, value)
    before = owner.const_get(name)
    owner.send(:remove_const, name)
    owner.const_set(name, value)
    yield
  ensure
    owner.send(:remove_const, name)
    owner.const_set(name, before)
  end
end

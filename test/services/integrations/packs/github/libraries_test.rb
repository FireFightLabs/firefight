require "test_helper"

module Integrations
  module Packs
    class Github
      class LibrariesTest < ActiveSupport::TestCase
        setup do
          @workspace = workspaces(:slack_workspace_one)
          FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
          @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
          @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
          @pack = Github.new(@integration, box_key: "investigation-1")
          CodeReading.any_instance.stubs(:prepare).returns({})
        end

        test "an installed library is found by its ecosystem and searched inside its own folder" do
          CodeReading.any_instance.expects(:exec).with { |repo, argv:, **| repo == "acme/web" && argv.last == "pg" && argv[3] == "find" }
                     .returns("stdout" => "FOUND\t8.11.3\t/runs/acme-web/node_modules/pg\n", "commit" => "abc123")
          CodeReading.any_instance.expects(:exec).with { |_repo, argv:, **| argv.drop(3) == [ "look", "/runs/acme-web/node_modules/pg", "search", "idleTimeout", "60" ] }
                     .returns("stdout" => "./lib/pool.js:12: idleTimeoutMillis = 10000\n", "commit" => "abc123")

          text = @pack.library_source(environment_row: @row, arguments: { "repo" => "acme/web", "library" => "pg", "pattern" => "idleTimeout" })

          assert_equal "pg 8.11.3, installed for acme/web at abc123\n./lib/pool.js:12: idleTimeoutMillis = 10000\n", text
        end

        test "a name that is not installed, or not a package name, is said" do
          CodeReading.any_instance.stubs(:exec).returns("stdout" => "MISSING\n", "commit" => "abc123")

          assert_match "is not installed", @pack.library_source(environment_row: @row, arguments: { "repo" => "acme/web", "library" => "pgx" })
          assert_raises(Integrations::Error) { @pack.library_source(environment_row: @row, arguments: { "repo" => "acme/web", "library" => "../etc" }) }
          assert_raises(Integrations::Error) { @pack.library_source(environment_row: @row, arguments: { "repo" => "acme/web", "library" => "-json" }) }
        end

        test "the scripts find a node package and read inside it, never outside" do
          Dir.mktmpdir do |repo|
            FileUtils.mkdir_p(File.join(repo, "node_modules", "pg", "lib"))
            File.write(File.join(repo, "node_modules", "pg", "package.json"), { version: "8.11.3" }.to_json)
            File.write(File.join(repo, "node_modules", "pg", "lib", "pool.js"), "const idleTimeoutMillis = 10000\n")

            found, = Open3.capture2("bash", "-c", Libraries::FIND, "find", "pg", chdir: repo)
            assert_equal "FOUND\t8.11.3\t#{File.realpath(repo)}/node_modules/pg\n", found.sub(repo, File.realpath(repo))

            dir = found.chomp.split("\t").last
            read, = Open3.capture2("bash", "-c", Libraries::LOOK, "look", dir, "read", "lib/pool.js", "10")
            assert_equal "const idleTimeoutMillis = 10000\n", read
            outside, = Open3.capture2("bash", "-c", Libraries::LOOK, "look", dir, "read", "../../../etc/passwd", "10")
            assert_includes [ "OUTSIDE\n", "MISSING\n" ], outside
            File.symlink("/etc/hostname", File.join(repo, "node_modules", "pg", "lib", "escape.js"))
            linked, = Open3.capture2("bash", "-c", Libraries::LOOK, "look", dir, "read", "lib/escape.js", "10")
            assert_equal "OUTSIDE\n", linked, "a link inside the library pointing outside it is never read"
          end
        end
      end
    end
  end
end

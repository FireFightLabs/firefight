require "test_helper"

module Integrations
  module Sandboxes
    # How the sandbox's command service prepares a copy with a repository's setup, and packs and unpacks what a prepared
    # copy installed, against the service itself over a real socket. Who a command runs as is left out, since that needs
    # the box's users, and the folders the box keeps are temporary ones here.
    class SetupTest < ActiveSupport::TestCase
      setup do
        load_server
        FileUtils.stubs(:chown)
        @replaced = {}
        @constants = {}
        @root = Dir.mktmpdir("sandbox-setup")
        set_constant(::Sandbox, :RUNS, File.join(@root, "runs"))
        set_constant(::Sandbox::Archive, :MISE_INSTALLS, File.join(@root, "mise", "installs"))
        FileUtils.mkdir_p([ ::Sandbox::RUNS, ::Sandbox::Archive::MISE_INSTALLS ])
        ran = @ran = []
        original = ::Sandbox.method(:run)
        replace(::Sandbox, :run) do |argv, **options|
          ran << { argv: argv, env: options[:env] || {} }
          next { "stdout" => "", "stderr" => "", "exit_code" => 0 } if %w[mise redis-server psql].include?(argv.first) || argv.first.to_s.end_with?("pg_ctl")

          original.call(argv, **options, user: nil)
        end
        replace(::Sandbox::Repos, :commit) { |_name, ref| ref }
        replace(::Sandbox::Repos, :run_copy) { |name, sha| File.join(::Sandbox::RUNS, "#{name}-#{sha}").tap { |dir| FileUtils.mkdir_p(File.join(dir, ".git", "info")) } }
        ::Sandbox::Services::STARTED.clear
        @server = TCPServer.new("127.0.0.1", 0)
        @accepting = Thread.new { loop { Thread.new(@server.accept) { |socket| ::Sandbox::Http.handle(socket) } } }
        @client = Client.new(Box.new(ref: "box", address: "http://127.0.0.1:#{@server.addr[1]}", key: ::Sandbox::KEY))
      end

      teardown do
        @accepting.kill
        @server.close
        @replaced.each { |(owner, name), original| owner.define_singleton_method(name, original) }
        @constants.each { |(owner, name), value| set_constant(owner, name, value, keep: false) }
        ::Sandbox::Services::STARTED.clear
        FileUtils.rm_rf(@root)
      end

      test "a copy is prepared with the setup's services and variables, then its commands in order, stopping at one that fails" do
        copy = copy_of("acme__api", "aaa")
        File.write(File.join(copy, "Gemfile.lock"), "GEM\n")
        failing = "bin/rails db:prepare"
        ran = @ran
        replace(::Sandbox, :run) do |argv, **options|
          ran << { argv: argv, env: options[:env] || {} }
          { "stdout" => "", "stderr" => argv.last == failing ? "no database" : "", "exit_code" => argv.last == failing ? 1 : 0 }
        end
        setup = { "services" => [ { "name" => "redis", "port" => 6380 }, { "name" => "mysql" } ],
                  "env" => { "RAILS_ENV" => "test", "PATH" => "/elsewhere", "MISE_YES" => "0" }, "commands" => [ "bin/setup", failing, "never" ] }

        prepared = @client.prepare(repository: "acme__api", ref: "aaa", setup: setup)

        assert_equal [ "sh -c bundle config set --local path vendor/bundle && bundle install --jobs 4" ], prepared["prepared"].map { |step| step["command"] }
        assert_equal [ "bin/setup", failing ], prepared["setup"].map { |step| step["command"] }, "a failing command stops the rest"
        assert_equal [ "mysql" ], prepared["left_out"]
        command = @ran.find { |run| run[:argv].last == "bin/setup" }
        assert_equal [ "mise", "exec", "--", "sh", "-c", "bin/setup" ], command[:argv]
        assert_equal "redis://127.0.0.1:6380/0", command[:env]["REDIS_URL"]
        assert_equal "test", command[:env]["RAILS_ENV"]
        assert_equal "1", command[:env]["MISE_YES"], "the box's own settings stay"
        refute command[:env].key?("PATH"), "a setup cannot move PATH"
        refute File.exist?(File.join(copy, ::Sandbox::Prepare::MARKER)), "a copy whose setup failed is prepared again next time"
      end

      test "a command in the copy runs with the setup's services and variables, a named service on the setup's port" do
        copy_of("acme__api", "aaa")
        setup = { "services" => [ { "name" => "redis", "port" => 6390 } ], "env" => { "RAILS_ENV" => "test" } }

        @client.exec(repository: "acme__api", ref: "aaa", argv: [ "true" ], where: Client::IN_COPY, services: [ "redis" ], setup: setup)

        command = @ran.find { |run| run[:argv] == [ "mise", "exec", "--", "true" ] }
        assert_equal "redis://127.0.0.1:6390/0", command[:env]["REDIS_URL"]
        assert_equal "test", command[:env]["RAILS_ENV"]
      end

      test "Postgres takes the role and database the setup's CI named, and refuses a name it cannot quote" do
        File.stubs(:directory?).returns(true)
        env = ::Sandbox::Services.start([ { "name" => "postgres", "port" => 5433, "env" => { "POSTGRES_USER" => "app", "POSTGRES_DB" => "app_test" } } ])

        assert_equal "postgres://app@127.0.0.1:5433/app_test", env["DATABASE_URL"]
        sql = @ran.select { |run| run[:argv].first == "psql" }.map { |run| run[:argv].last }
        assert(sql.any? { |statement| statement.include?(%(CREATE ROLE "app")) })
        assert(sql.any? { |statement| statement.include?(%(CREATE DATABASE "app_test" OWNER "app")) })
        error = assert_raises(::Sandbox::Refused) do
          ::Sandbox::Services.start([ { "name" => "postgres", "port" => 5433, "env" => { "POSTGRES_USER" => "app\"; DROP" } } ])
        end
        assert_match "is not a name Postgres takes", error.message
        assert_raises(::Sandbox::Refused) { ::Sandbox::Services.start([ { "name" => "postgres", "port" => 5434 } ]) }
      end

      test "a service the sandbox cannot start is answered in a sentence" do
        error = assert_raises(Error) { @client.start_services([ "mysql" ]) }

        assert_equal "The sandbox cannot start mysql. It can start postgres and redis.", error.message
        assert_equal "redis://127.0.0.1:6379/0", @client.start_services([ "redis" ]).dig("env", "REDIS_URL")
      end

      test "what a prepared copy installed is packed and handed to another copy, which starts from it" do
        copy = copy_of("acme__api", "aaa")
        FileUtils.mkdir_p([ File.join(copy, "node_modules", "left-pad"), File.join(copy, ".venv", "bin"), File.join(copy, "app") ])
        File.write(File.join(copy, "node_modules", "left-pad", "index.js"), "module.exports = 1\n")
        File.write(File.join(copy, ".venv", "bin", "pytest"), "#!#{copy}/.venv/bin/python\nimport pytest\n")
        File.write(File.join(copy, "app", "code.rb"), "not installed\n")
        FileUtils.touch(File.join(copy, ::Sandbox::Prepare::MARKER))
        FileUtils.mkdir_p(File.join(::Sandbox::Archive::MISE_INSTALLS, "ruby", "3.4.1", "bin"))
        File.write(File.join(::Sandbox::Archive::MISE_INSTALLS, "ruby", "3.4.1", "bin", "ruby"), "ruby\n")
        archive = File.join(@root, "kept.tar.gz")

        @client.download_archive(repository: "acme__api", ref: "aaa", path: archive, limit: 10.megabytes)
        FileUtils.rm_rf(Dir.glob(File.join(::Sandbox::Archive::MISE_INSTALLS, "*")))
        restored = @client.upload_archive(repository: "acme__api", ref: "bbb", path: archive)

        later = File.join(::Sandbox::RUNS, "acme__api-bbb")
        assert restored["restored"]
        assert_equal "module.exports = 1\n", File.read(File.join(later, "node_modules", "left-pad", "index.js"))
        assert File.read(File.join(later, ".venv", "bin", "pytest")).start_with?("#!#{later}/.venv/bin/python"), "the virtualenv's scripts name the new copy"
        refute File.exist?(File.join(later, "app", "code.rb")), "only what preparing installs is taken"
        refute File.exist?(File.join(later, ::Sandbox::Prepare::MARKER)), "the copy still runs its installers once"
        assert File.exist?(File.join(later, ::Sandbox::Prepare::RESTORED))
        assert File.exist?(File.join(::Sandbox::Archive::MISE_INSTALLS, "ruby", "3.4.1", "bin", "ruby")), "the tool versions come back too"
        assert_empty Dir.glob(File.join(::Sandbox::RUNS, ".{archive,restore,upload}-*")), "nothing is left behind"
      end

      test "a restored copy runs each installer once more, npm without starting from nothing" do
        copy = copy_of("acme__api", "bbb")
        File.write(File.join(copy, "package-lock.json"), "{}")
        FileUtils.touch(File.join(copy, ::Sandbox::Prepare::RESTORED))

        prepared = @client.prepare(repository: "acme__api", ref: "bbb")

        assert prepared["restored"]
        assert_equal [ "npm install --no-save --no-fund --no-audit" ], prepared["prepared"].map { |step| step["command"] }
      end

      test "an archive cannot put anything outside what preparing installs, nor follow a link out of the copy" do
        crafted = File.join(@root, "crafted")
        FileUtils.mkdir_p([ File.join(crafted, "copy", "node_modules"), File.join(crafted, "copy", "elsewhere") ])
        File.write(File.join(crafted, "copy", "node_modules", "ok.js"), "ok\n")
        File.write(File.join(crafted, "copy", "Gemfile"), "planted\n")
        File.symlink(File.join(crafted, "copy", "elsewhere"), File.join(crafted, "copy", ".venv"))
        archive = File.join(@root, "crafted.tar.gz")
        system("tar", "-C", crafted, "-czf", archive, "copy", exception: true)

        @client.upload_archive(repository: "acme__api", ref: "ccc", path: archive)

        later = File.join(::Sandbox::RUNS, "acme__api-ccc")
        assert File.exist?(File.join(later, "node_modules", "ok.js"))
        refute File.exist?(File.join(later, "Gemfile"))
        refute File.exist?(File.join(later, ".venv")), "a link in the archive is not followed"
      end

      test "what decides a copy's installs is its lockfiles and the box's tools, not the rest of the repository" do
        work = File.join(@root, "work")
        FileUtils.mkdir_p(work)
        git = ->(*arguments) { system("git", "-C", work, *arguments, exception: true, out: File::NULL, err: File::NULL) }
        git.call("init", "-q", "-b", "main")
        File.write(File.join(work, "Gemfile.lock"), "GEM\n  rails (8.0)\n")
        File.write(File.join(work, "app.rb"), "1\n")
        git.call("add", ".")
        git.call("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "one")
        first = `git -C #{work} rev-parse HEAD`.strip
        File.write(File.join(work, "app.rb"), "2\n")
        git.call("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qam", "two")
        second = `git -C #{work} rev-parse HEAD`.strip
        File.write(File.join(work, "Gemfile.lock"), "GEM\n  rails (8.1)\n")
        git.call("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qam", "three")
        third = `git -C #{work} rev-parse HEAD`.strip
        replace(::Sandbox::Repos, :bare) { |_name| File.join(work, ".git") }
        replace(::Sandbox::Prepare, :toolchain) { "the box's tools" }

        digests = [ first, second, third ].map { |sha| @client.prepare_state(repository: "acme__api", ref: sha)["lock_digest"] }

        assert_equal digests[0], digests[1], "a change outside the lockfiles keeps what was installed"
        refute_equal digests[1], digests[2], "a lockfile change installs again"
      end

      private

      def copy_of(name, sha) = ::Sandbox::Repos.run_copy(name, sha)

      def load_server
        return if defined?(::Sandbox::Runs)

        given = ENV.to_h.slice("SANDBOX_KEY", "SANDBOX_PROGRESS_DIR")
        ENV["SANDBOX_KEY"] = "test-box-key"
        ENV["SANDBOX_PROGRESS_DIR"] = Dir.mktmpdir("sandbox-progress")
        load Rails.root.join("sandbox/server.rb").to_s
      ensure
        %w[SANDBOX_KEY SANDBOX_PROGRESS_DIR].each { |name| ENV[name] = given[name] } if given
      end

      def replace(owner, name, &block)
        @replaced[[ owner, name ]] ||= owner.method(name)
        owner.define_singleton_method(name, &block)
      end

      def set_constant(owner, name, value, keep: true)
        @constants[[ owner, name ]] ||= owner.const_get(name) if keep
        owner.send(:remove_const, name)
        owner.const_set(name, value)
      end
    end
  end
end

require "test_helper"

module Integrations
  module Packs
    class Github
      # The script a code fix runs in the sandbox, run here for real against a repository, with a stand-in for the agent.
      class FixingScriptTest < ActiveSupport::TestCase
        AGENT = <<~SH.freeze
          #!/bin/sh
          git mv old.rb renamed.rb
          rm gone.txt
          printf 'pool: 10\\n' > 'config/data base.yml'
          ln -s /etc/hostname link
          git -c user.email=a@b -c user.name=agent commit -qam "agent committed anyway"
          git config core.hooksPath /tmp/elsewhere
          printf 'not part of it' > node_modules/installed.js
        SH

        test "every change against where the copy started is listed, whatever the agent did, and the copy is put back" do
          Dir.mktmpdir do |root|
            repo = File.join(root, "repo")
            bin = File.join(root, "bin")
            FileUtils.mkdir_p([ File.join(repo, "config"), File.join(repo, "node_modules"), bin ])
            File.write(File.join(repo, "old.rb"), "puts 1\n")
            File.write(File.join(repo, "gone.txt"), "x\n")
            File.write(File.join(repo, "config", "data base.yml"), "pool: 2\n")
            File.write(File.join(repo, ".gitignore"), "")
            git(repo, "init", "-q")
            git(repo, "add", "-A")
            git(repo, "-c", "user.email=a@b", "-c", "user.name=t", "commit", "-qm", "start")
            File.write(File.join(repo, ".git", "info", "exclude"), "/node_modules\n")
            start = git(repo, "rev-parse", "HEAD").strip
            File.write(File.join(bin, "opencode"), AGENT)
            File.chmod(0o755, File.join(bin, "opencode"))

            output, status = Open3.capture2({ "PATH" => "#{bin}:#{ENV.fetch('PATH')}" }, "bash", "-c", Fixing::RUN, "opencode", "{}", "brief", "x/y", chdir: repo)
            change = Github.new(Integration.new(provider: "github")).send(:read_change, output)

            assert status.success?, output
            assert_equal 0, change.agent_exit
            assert_equal start, change.base
            assert_equal [ "config/data base.yml", "gone.txt", "link", "old.rb", "renamed.rb" ], change.files.keys.sort
            assert_nil change.files["old.rb"]
            assert_nil change.files["gone.txt"]
            assert_equal "pool: 10\n", Base64.decode64(change.files["config/data base.yml"][:content])
            assert_equal [ "120000", "/etc/hostname" ], [ change.files["link"][:mode], Base64.decode64(change.files["link"][:content]) ]
            assert_equal start, git(repo, "rev-parse", "HEAD").strip, "the copy is back where it started"
            assert_empty git(repo, "status", "--porcelain").strip
            assert_empty git(repo, "config", "--get", "core.hooksPath").strip
            assert File.exist?(File.join(repo, "node_modules", "installed.js")), "what preparing installed stays"
          end
        end

        private

        def git(dir, *args)
          output, = Open3.capture2("git", *args, chdir: dir)
          output
        end
      end
    end
  end
end

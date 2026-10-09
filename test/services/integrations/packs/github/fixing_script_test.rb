require "test_helper"

module Integrations
  module Packs
    class Github
      # The scripts a code fix runs in the sandbox, run here for real against repositories, with a stand-in for the agent
      # and a bare repository standing where Firefight's git gate is, which git reaches the same way by its address.
      class FixingScriptTest < ActiveSupport::TestCase
        AGENT = <<~SH.freeze
          #!/bin/sh
          echo '{"type":"text","part":{"text":"Renaming old.rb."}}'
          git mv old.rb renamed.rb
          git commit -qm "agent committed part of it"
          rm gone.txt
          printf 'pool: 10\\n' > 'config/data base.yml'
          git config core.hooksPath /tmp/elsewhere
          printf 'not part of it' > node_modules/installed.js
        SH

        test "the agent works on the change's branch, what it left is committed, the result is kept for the push, and the copy is put back" do
          Dir.mktmpdir do |root|
            gate, copy, start = repository_with_gate(root) do |work|
              FileUtils.mkdir_p([ File.join(work, "config"), File.join(work, "node_modules") ])
              File.write(File.join(work, "old.rb"), "puts 1\n")
              File.write(File.join(work, "gone.txt"), "x\n")
              File.write(File.join(work, "config", "data base.yml"), "pool: 2\n")
            end
            File.write(File.join(copy, ".git", "info", "exclude"), "/node_modules\n")
            FileUtils.mkdir_p(File.join(copy, "node_modules"))
            progress = File.join(root, "progress.log")

            output = run_script(root, copy, AGENT, gate, env: { "SANDBOX_PROGRESS" => progress })
            change = read(output)

            assert_equal 0, change.agent_exit
            assert_equal start, change.base
            assert change.commit, output
            assert_equal [ "config/data base.yml", "gone.txt", "old.rb", "renamed.rb" ], change.counts.keys.sort
            assert_equal [ 1, 1 ], change.counts["config/data base.yml"]
            assert_equal change.commit, git(copy, "rev-parse", "refs/halon/halon/fix-1").strip, "kept for the push"
            assert_equal "Fix the pool", git(copy, "log", "-1", "--format=%s", change.commit).strip, "what was left is committed with the title"
            assert_equal start, git(copy, "rev-parse", "HEAD").strip, "the copy is back where it started"
            assert_empty git(copy, "status", "--porcelain").strip
            assert_empty git(copy, "config", "--get", "core.hooksPath").strip
            assert_empty git(copy, "branch", "--list", "halon/fix-1").strip
            assert File.exist?(File.join(copy, "node_modules", "installed.js")), "what preparing installed stays"
            assert_equal "{\"type\":\"text\",\"part\":{\"text\":\"Renaming old.rb.\"}}\n", File.read(progress), "what the agent prints is told as it goes"
            assert_includes change.log, "Renaming old.rb."
            assert_includes change.diff, "+pool: 10"
            assert_empty git(gate, "branch", "--list", "halon/fix-1").strip, "nothing is pushed before the review"
          end
        end

        test "the agent has a temporary directory of its own, set as TMPDIR, and it is gone once the run ends" do
          Dir.mktmpdir do |root|
            gate, copy, = repository_with_gate(root)
            agent = <<~SH
              #!/bin/sh
              printf 'started\\n' > "$TMPDIR/server.log" && echo "TMP $TMPDIR $(cat "$TMPDIR/server.log")"
              printf 'b\\n' > b.txt
            SH

            change = read(run_script(root, copy, agent, gate))

            tmp, said = change.log[/^TMP (.+)$/, 1].to_s.split
            assert_equal "started", said, change.log
            assert_not_equal Dir.tmpdir, tmp
            assert_not Dir.exist?(tmp), "it goes with the run"
            assert_equal [ "b.txt" ], change.counts.keys, "nothing it wrote there is part of the change"
          end
        end

        test "the reviewed change is pushed through the gate to its new branch, and a branch someone made first is never overwritten" do
          Dir.mktmpdir do |root|
            gate, copy, = repository_with_gate(root)
            change = read(run_script(root, copy, "#!/bin/sh\nprintf 'b\\n' > b.txt\n", gate))

            pushed = push(copy, gate, "halon/fix-1", "")

            assert_match Fixing::PUSHED, pushed
            assert_equal change.commit, git(gate, "rev-parse", "refs/heads/halon/fix-1").strip

            other = read(run_script(root, copy, "#!/bin/sh\nprintf 'c\\n' > c.txt\n", gate, branch: "halon/fix-2"))
            git(copy, "push", "-q", gate, "#{change.commit}:refs/heads/halon/fix-2")
            refused = push(copy, gate, "halon/fix-2", "")
            assert_no_match Fixing::PUSHED, refused
            assert_match "stale info", refused
            assert_equal change.commit, git(gate, "rev-parse", "refs/heads/halon/fix-2").strip, "what someone made first stays"
            assert other.commit
          end
        end

        test "an agent that merges a base which moved with a conflicting change pushes a merge commit with both parents" do
          Dir.mktmpdir do |root|
            gate, copy, head, base = conflicted_pull_request(root)
            resolve = <<~SH
              #!/bin/sh
              git merge -q refs/remotes/firefight/main > /dev/null 2>&1
              printf 'pool: 20\\ntimeout: 5\\n' > config.yml
              git add config.yml
              git commit -q --no-edit
            SH

            change = read(run_script(root, copy, resolve, gate, branch: "fix-pool"))
            pushed = push(copy, gate, "fix-pool", head)

            assert_match Fixing::PUSHED, pushed
            assert_empty change.unresolved
            assert_equal [ change.commit, head, base ], git(gate, "rev-list", "--parents", "-n", "1", "refs/heads/fix-pool").split
            assert_equal "pool: 20\ntimeout: 5\n", git(gate, "show", "refs/heads/fix-pool:config.yml")
            assert_equal "base only\n", git(gate, "show", "refs/heads/fix-pool:notes.txt"), "what only the base changed comes in"
            assert_equal "", git(gate, "merge-tree", "--write-tree", "--name-only", "refs/heads/main", "refs/heads/fix-pool").lines.drop(1).join.strip,
                         "the branch now merges into main cleanly"
          end
        end

        test "after the base moved and was merged in, only what the pull request changes is counted, checked and handed to the review" do
          Dir.mktmpdir do |root|
            gate, copy, = conflicted_pull_request(root)
            resolve = <<~SH
              #!/bin/sh
              git merge -q refs/remotes/firefight/main > /dev/null 2>&1
              printf 'pool: 20\\ntimeout: 5\\n' > config.yml
              git add config.yml
              git commit -q --no-edit
            SH

            change = read(run_script(root, copy, resolve, gate, branch: "fix-pool"))

            assert_equal [ "config.yml" ], change.counts.keys, "notes.txt and settings.json came from main, so they are not the pull request's"
            assert_includes change.diff, "+timeout: 5"
            assert_not_includes change.diff, "notes.txt"
            assert_equal [ "config.yml" ], change.checks.map(&:name).map { |name| name.split.last }.uniq, "the broken JSON main brought is not checked"
            assert change.merged
            assert_equal [ "config.yml", "notes.txt", "settings.json" ], change.touched.sort
            assert_equal [ "config.yml" ], change.updated_paths
          end
        end

        test "a test that cannot run without a database is reported as could not run, and the test covering a changed file runs" do
          Dir.mktmpdir do |root|
            gate, copy, = repository_with_gate(root) do |work|
              FileUtils.mkdir_p([ File.join(work, "app/models"), File.join(work, "test/models"), File.join(work, "bin") ])
              File.write(File.join(work, "app/models/pool.rb"), "class Pool; end\n")
              File.write(File.join(work, "test/models/pool_test.rb"), "# covers Pool\n")
              File.write(File.join(work, "bin/rails"), "#!/bin/sh\necho 'PG::ConnectionBad: connection to server on socket \"/run/postgresql/.s.PGSQL.5432\" failed'\nexit 1\n")
              File.chmod(0o755, File.join(work, "bin/rails"))
            end

            change = read(run_script(root, copy, "#!/bin/sh\nprintf 'class Pool\\n  SIZE = 10\\nend\\n' > app/models/pool.rb\n", gate))

            check = change.checks.find { |found| found.name == "bin/rails test test/models/pool_test.rb" }
            assert check, change.checks.map(&:name).inspect
            assert_equal CodeChecks::COULD_NOT_RUN, check.status
            assert_equal "no database was available", check.reason
          end
        end

        test "conflict markers left in a file are named, and a branch that moved since the change began refuses the push" do
          Dir.mktmpdir do |root|
            gate, copy, head, = conflicted_pull_request(root)
            left = read(run_script(root, copy, "#!/bin/sh\ngit merge -q refs/remotes/firefight/main > /dev/null 2>&1\ntrue\n", gate, branch: "fix-pool"))
            assert_equal [ "config.yml" ], left.unresolved

            fine = read(run_script(root, copy, "#!/bin/sh\nprintf 'x\\n' > extra.txt\n", gate, branch: "fix-pool"))
            mover = File.join(root, "mover")
            git(root, "clone", "-q", "-b", "fix-pool", gate, mover)
            File.write(File.join(mover, "late.txt"), "late\n")
            git(mover, "add", "-A")
            commit(mover, "pushed meanwhile")
            git(mover, "push", "-q", "origin", "fix-pool")

            refused = push(copy, gate, "fix-pool", head)
            assert_no_match Fixing::PUSHED, refused
            assert_match "stale info", refused
            assert fine.commit
          end
        end

        test "the agent's exit code comes through the pipe, a change sent back starts from the earlier one, and nothing changed says so" do
          Dir.mktmpdir do |root|
            gate, copy, = repository_with_gate(root)
            failing = read(run_script(root, copy, "#!/bin/sh\necho b > a.txt\necho failing\nexit 3\n", gate))
            assert_equal 3, failing.agent_exit
            assert_equal "failing", failing.log

            again = read(run_script(root, copy, "#!/bin/sh\necho c >> a.txt\n", gate, earlier: failing.commit))
            assert_equal "b\nc\n", git(copy, "show", "#{again.commit}:a.txt"), "the earlier change is carried into the second"

            nothing = run_script(root, copy, "#!/bin/sh\ntrue\n", gate)
            assert_match(/^NOTHING$/, nothing)
            assert_nil read(nothing).commit
          end
        end

        test "the agent's session is named for a pause, a continued change resumes it, and a paused change is saved to a branch of its own" do
          Dir.mktmpdir do |root|
            gate, copy, = repository_with_gate(root)
            agent = <<~SH
              #!/bin/sh
              echo "$@" > "#{root}/args"
              echo '{"type":"step_start","sessionID":"ses_123","part":{}}'
              printf 'b\\n' > b.txt
            SH

            change = read(run_script(root, copy, agent, gate, branch: "fix-pool"))
            assert_equal "ses_123", change.agent_session
            assert_no_match "--session", File.read(File.join(root, "args"))

            saved = push(copy, gate, "halon/fix-saved", "", from: "fix-pool")
            assert_match Fixing::PUSHED, saved
            assert_equal change.commit, git(gate, "rev-parse", "refs/heads/halon/fix-saved").strip, "the work is on its own branch"
            assert_empty git(gate, "branch", "--list", "fix-pool").strip, "and not on the branch it was for"

            again = read(run_script(root, copy, agent.sub("b.txt", "c.txt"), gate, branch: "fix-pool", earlier: change.commit, resume: "ses_123"))
            assert_match "run --session ses_123 --model", File.read(File.join(root, "args"))
            assert_equal "b\n", git(copy, "show", "#{again.commit}:b.txt"), "it carries on from what it saved"
          end
        end

        test "no credential is in the script's arguments or the agent's environment, and the agent reads its config from the file it is given" do
          Dir.mktmpdir do |root|
            gate, copy, = repository_with_gate(root)
            agent = <<~SH
              #!/bin/sh
              tr '\\0' ' ' < /proc/$PPID/cmdline > "#{root}/parent"
              env > "#{root}/env"
              cat "$OPENCODE_CONFIG" > "#{root}/config"
              printf 'b\\n' > b.txt
            SH

            change = read(run_script(root, copy, agent, gate))

            assert change.commit
            assert_match "Fix the pool", File.read(File.join(root, "parent")), "the script's own arguments were read"
            assert_no_match "secret-token", File.read(File.join(root, "parent"))
            assert_no_match(/secret-token|halon:|Authorization/, File.read(File.join(root, "env")))
            assert_equal "{\"apiKey\":\"secret-token\"}", File.read(File.join(root, "config"))
          end
        end

        test "the changed files are checked with what the box has" do
          Dir.mktmpdir do |root|
            gate, copy, = repository_with_gate(root) do |work|
              File.write(File.join(work, "settings.json"), "{}\n")
              File.write(File.join(work, "untouched.json"), "not json\n")
            end
            bin = File.join(root, "bin")
            FileUtils.mkdir_p(bin)
            File.write(File.join(bin, "actionlint"), "#!/bin/sh\necho \"$1:1: unknown key\"\nexit 1\n")
            File.chmod(0o755, File.join(bin, "actionlint"))

            change = read(run_script(root, copy, "#!/bin/sh\nprintf '{ broken' > settings.json\nmkdir -p .github/workflows\nprintf 'on: push\\n' > .github/workflows/ci.yml\n", gate))

            checks = change.checks.to_h { |check| [ check.name, check.status ] }
            assert_equal CodeChecks::FAILED, checks["actionlint .github/workflows/ci.yml"]
            if system("command -v python3 > /dev/null 2>&1")
              assert_equal CodeChecks::FAILED, checks["json settings.json"]
            else
              assert_not checks.key?("json settings.json"), "a check whose tool the box lacks is skipped"
            end
            assert_not checks.key?("json untouched.json"), "only the files the change touched are checked"
          end
        end

        test "a gate that cannot be fetched from stops the change before the agent starts" do
          Dir.mktmpdir do |root|
            _gate, copy, = repository_with_gate(root)

            output = run_script(root, copy, "#!/bin/sh\necho ran > ran.txt\n", File.join(root, "nowhere.git"))

            assert output.start_with?(Fixing::FETCH_FAILED)
            assert_not File.exist?(File.join(copy, "ran.txt"))
          end
        end

        private

        # A bare repository where the gate would be, holding main, and a copy of it at main's head the way the sandbox
        # clones one from the box's own copy.
        def repository_with_gate(root)
          work = File.join(root, "work")
          FileUtils.mkdir_p(work)
          File.write(File.join(work, "a.txt"), "a\n")
          yield work if block_given?
          git(work, "init", "-q", "-b", "main")
          git(work, "add", "-A")
          commit(work, "start")
          gate = File.join(root, "gate.git")
          git(root, "clone", "-q", "--bare", work, gate)
          copy = File.join(root, "copy")
          git(root, "clone", "-q", gate, copy)
          git(copy, "checkout", "-q", "--detach", "main")
          [ gate, copy, git(copy, "rev-parse", "HEAD").strip ]
        end

        # main and a pull request's branch changed the same line, and main changed a file the branch did not. The copy
        # is at the branch's head as the box had it before main moved.
        def conflicted_pull_request(root)
          gate, copy, = repository_with_gate(root) do |work|
            File.write(File.join(work, "config.yml"), "pool: 5\n")
            File.write(File.join(work, "notes.txt"), "start\n")
          end
          git(copy, "checkout", "-q", "-b", "fix-pool")
          File.write(File.join(copy, "config.yml"), "pool: 10\n")
          commit(copy, "raise the pool", all: true)
          git(copy, "push", "-q", "origin", "fix-pool")
          head = git(copy, "rev-parse", "HEAD").strip
          other = File.join(root, "other")
          git(root, "clone", "-q", gate, other)
          File.write(File.join(other, "config.yml"), "pool: 20\n")
          File.write(File.join(other, "notes.txt"), "base only\n")
          File.write(File.join(other, "settings.json"), "{ broken\n")
          git(other, "add", "settings.json")
          commit(other, "raise it further", all: true)
          git(other, "push", "-q", "origin", "main")
          base = git(other, "rev-parse", "HEAD").strip
          git(copy, "checkout", "-q", "--detach", head)
          git(copy, "branch", "-q", "-D", "fix-pool")
          [ gate, copy, head, base ]
        end

        def run_script(root, copy, agent, gate, branch: "halon/fix-1", earlier: "", env: {}, resume: "")
          bin = File.join(root, "bin")
          FileUtils.mkdir_p(bin)
          File.write(File.join(bin, "opencode"), agent)
          File.chmod(0o755, File.join(bin, "opencode"))
          output, = Open3.capture2({ "PATH" => "#{bin}:#{ENV.fetch('PATH')}" }.merge(env), "bash", "-c", Fixing::RUN, "opencode", "brief", "x/y",
                                   earlier.to_s, gate, "main", branch, "Fix the pool", resume, chdir: copy,
                                   stdin_data: "#{Base64.strict_encode64('halon:secret-token')}\n{\"apiKey\":\"secret-token\"}\n")
          output
        end

        def push(copy, gate, branch, lease, from: branch)
          output, = Open3.capture2("bash", "-c", Fixing::PUSH, "push", gate, branch, lease, from, chdir: copy,
                                   stdin_data: "#{Base64.strict_encode64('halon:push-token')}\n")
          output
        end

        def read(output) = Github.new(Integration.new(provider: "github")).send(:read_change, output)

        def commit(dir, message, all: false)
          git(dir, "-c", "user.email=a@b", "-c", "user.name=t", "commit", "-q", *([ "-a" ] if all), "-m", message)
        end

        def git(dir, *args)
          output, = Open3.capture2("git", *args, chdir: dir)
          output
        end
      end
    end
  end
end

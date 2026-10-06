require "test_helper"

module Integrations
  module Packs
    class BitbucketTest < ActiveSupport::TestCase
      REPO = "/repositories/acme/web".freeze
      HEAD = "c4e4267d46e638ac6f257d117ab448c280d01c0b".freeze
      BASE = "b586e23aa0e1f6c7c2f2b0c3d4e5f60718293a4b".freeze
      PIPELINE = "{11111111-2222-3333-4444-555555555555}".freeze
      STEP = "{66666666-7777-8888-9999-000000000000}".freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "bitbucket", name: "Bitbucket")
        @row = @integration.integration_environments.create!
        @row.store_fields!(Bitbucket::WORKSPACE => "acme")
        Bitbucket.store_credentials!(@row, Bitbucket::TOKEN => " bb-token ")
        @pack = Bitbucket.new(@integration, box_key: "investigation-1")
      end

      test "the token is the one credential, trimmed, the workspace a connect field, and every tool only reads but the ones that run a repository's own commands or change its pipelines" do
        settings = ConnectionSettings.of(@row.reload)
        assert_equal [ "acme", "bb-token" ], [ settings.field(Bitbucket::WORKSPACE), settings.credential(Bitbucket::TOKEN) ]
        assert_equal [ Bitbucket::TOKEN ], Bitbucket.credential_fields.map(&:key)
        assert_equal %w[run_tests rerun_pipeline run_pipeline cancel_pipeline], Bitbucket.tool_definitions.reject(&:read_only).map(&:name)
      end

      test "the connect form says what is wrong with a token or workspace before anything is saved" do
        assert_equal "Paste a token.", Bitbucket.credential_refusal({ Bitbucket::TOKEN => "" }, fields: { Bitbucket::WORKSPACE => "acme" })
        assert_match "workspace's id", Bitbucket.credential_refusal({ Bitbucket::TOKEN => "t" }, fields: { Bitbucket::WORKSPACE => "acme/web" })

        BitbucketApi.any_instance.stubs(:get).with("/repositories/acme", "pagelen" => 1).raises(BitbucketApi::Refused, "Bitbucket answered 401")
        assert_match "Bitbucket refused this token", Bitbucket.credential_refusal({ Bitbucket::TOKEN => "t" }, fields: { Bitbucket::WORKSPACE => "acme" })

        BitbucketApi.any_instance.stubs(:get).with("/repositories/acme", "pagelen" => 1).raises(BitbucketApi::NotFound, "Bitbucket answered 404")
        assert_equal "Bitbucket has no workspace acme that this token can see.", Bitbucket.credential_refusal({ Bitbucket::TOKEN => "t" }, fields: { Bitbucket::WORKSPACE => "acme" })

        BitbucketApi.any_instance.stubs(:get).with("/repositories/acme", "pagelen" => 1).returns("values" => [])
        assert_nil Bitbucket.credential_refusal({ Bitbucket::TOKEN => "t" }, fields: { Bitbucket::WORKSPACE => "acme" })
      end

      test "the health check reads the workspace and says why it failed" do
        BitbucketApi.any_instance.stubs(:get).with("/repositories/acme", "pagelen" => 1).returns("values" => [])
        assert_nothing_raised { @pack.check_health!(@row) }

        BitbucketApi.any_instance.stubs(:get).with("/repositories/acme", "pagelen" => 1).raises(BitbucketApi::Refused, "Bitbucket answered 401: Token expired")
        assert_equal "Bitbucket answered 401: Token expired", assert_raises(NativePack::Error) { @pack.check_health!(@row) }.message
      end

      test "the workspace's repositories are listed with their main branch, each linked at the address Bitbucket gives it" do
        list("/repositories/acme", [ { "full_name" => "acme/web", "mainbranch" => { "name" => "main" }, "updated_on" => "2026-10-01T10:00:00Z",
                                       "links" => { "html" => { "href" => "https://bitbucket.org/acme/web" } } } ], more: true)

        text = body(call(:list_repositories))

        assert_match "acme/web  main branch main  last update 2026-10-01T10:00:00Z", text
        assert_match "More repositories than these", text
        assert_match "last update 2026-10-01T10:00:00Z  https://bitbucket.org/acme/web", text
      end

      test "a pull request says who merged and approved it, its files and its page" do
        get("#{REPO}/pullrequests/42", {
          "id" => 42, "title" => "Pool size", "state" => "MERGED", "author" => { "display_name" => "Ana" },
          "source" => { "branch" => { "name" => "pool" } }, "destination" => { "branch" => { "name" => "main" } },
          "merge_commit" => { "hash" => "123148a92682" }, "closed_by" => { "display_name" => "Bo" }, "updated_on" => "2026-10-01T10:00:00Z",
          "participants" => [ { "approved" => true, "user" => { "display_name" => "Cy" } }, { "approved" => false, "user" => { "display_name" => "Di" } } ],
          "description" => "Raise the pool", "links" => { "html" => { "href" => "https://bitbucket.org/acme/web/pull-requests/42" } }
        })
        list("#{REPO}/pullrequests/42/diffstat", [ stat("config/database.yml", 1, 1) ])

        text = body(call(:pr_lookup, "repo" => "acme/web", "id" => 42))

        assert_match "State: merged as 123148a92682 by Bo", text
        assert_match "Approved by: Cy\n", text
        assert_match "config/database.yml (modified, +1 -1)", text
        assert_match "https://bitbucket.org/acme/web/pull-requests/42", text
      end

      test "a commit gives its author, its stats summed from its files, and its page" do
        get("#{REPO}/commit/#{HEAD}", { "hash" => HEAD, "author" => { "raw" => "Ana <ana@acme.dev>" }, "date" => "2026-10-01T10:00:00Z",
                                        "message" => "Raise the pool", "links" => { "html" => { "href" => "https://bitbucket.org/acme/web/commits/#{HEAD}" } } })
        list("#{REPO}/diffstat/#{HEAD}", [ stat("a.rb", 3, 1), stat("b.rb", 2, 0) ])

        text = body(call(:commit_lookup, "repo" => "acme/web", "sha" => HEAD))

        assert_match "Changes: +5 -1", text
        assert_match "https://bitbucket.org/acme/web/commits/#{HEAD}", text
        assert_match "sha must be a commit SHA", assert_raises(NativePack::Error) { call(:commit_lookup, "repo" => "acme/web", "sha" => "nope") }.message
      end

      test "deployments are newest first, named by their environment, and filtered by it" do
        deployments

        text = body(call(:recent_deployments, "repo" => "acme/web"))

        assert_equal [ "Production", "Staging", "Production" ], text.lines.first(3).map { |line| line.split("  ")[1] }
        assert_match "successful  by Ana  deployment {d2}  https://bitbucket.org/acme/web/pipelines/results/7", text
        assert_no_match "acme/web/deployments", text, "Bitbucket gives its deployments list no address, so only each release's pipeline is linked"
        assert_equal 2, body(call(:recent_deployments, "repo" => "acme/web", "deployment_environment" => "production")).lines.count { |line| line.include?("Production") }
      end

      test "merged pull requests are read by state, newest update first, since a time" do
        BitbucketApi.any_instance.expects(:get).with("#{REPO}/pullrequests", { "state" => "MERGED", "sort" => "-updated_on", "pagelen" => 50,
                                                                              "q" => "updated_on >= 2026-10-01T00:00:00Z" })
                    .returns("values" => [ { "id" => 7, "title" => "Pool", "updated_on" => "2026-10-02T00:00:00Z", "closed_by" => { "display_name" => "Bo" },
                                             "destination" => { "branch" => { "name" => "main" } }, "links" => { "html" => { "href" => "https://bitbucket.org/acme/web/pull-requests/7" } } } ])

        text = call(:merged_pull_requests, "repo" => "acme/web", "since" => "2026-10-01T00:00:00Z")

        assert_equal "PR #7  Pool  merged, last updated 2026-10-02T00:00:00Z, by Bo into main  https://bitbucket.org/acme/web/pull-requests/7", text
      end

      test "the running commit is the last production deployment that succeeded before the time, with the one before" do
        deployments

        text = call(:running_commit, "repo" => "acme/web", "at" => "2026-10-02T12:00:00Z")

        assert_match "Running in acme/web at 2026-10-02T12:00:00Z: #{HEAD}", text
        assert_match "compare_commits with base #{BASE} and head #{HEAD}", text
      end

      test "without a deployment the running commit is the main branch's tip at the time, said to be a guess" do
        list("#{REPO}/environments", [])
        list("#{REPO}/deployments", [])
        get(REPO, { "mainbranch" => { "name" => "main" } })
        list("#{REPO}/commits/main", [ { "hash" => "new", "date" => "2026-10-03T00:00:00Z" }, { "hash" => HEAD, "date" => "2026-10-02T10:00:00Z" },
                                       { "hash" => BASE, "date" => "2026-09-30T10:00:00Z" } ])

        text = call(:running_commit, "repo" => "acme/web", "at" => "2026-10-02T12:00:00Z")

        assert_match "Tip of main at that time: #{HEAD}", text
        assert_match "a guess from the main branch", text
        assert_match "compare_commits with base #{BASE} and head #{HEAD}", text
      end

      test "a comparison reads Bitbucket's range the other way round, and gives files, diffs, pull requests and owners" do
        spec = ERB::Util.url_encode("#{HEAD}..#{BASE}")
        list("#{REPO}/diffstat/#{spec}", [ stat("db/migrate/1_pool.rb", 3, 0, "added"), stat("app/pool.rb", 1, 1) ])
        text_at("#{REPO}/diff/#{spec}", "diff --git a/db/migrate/1_pool.rb b/db/migrate/1_pool.rb\n+add\ndiff --git a/app/pool.rb b/app/pool.rb\n-old\n+new\n")
        list("#{REPO}/commits", [ { "hash" => HEAD, "date" => "2026-10-02T10:00:00Z", "author" => { "raw" => "Ana" }, "message" => "Raise the pool\n\nbody" } ])
        get("#{REPO}/commit/#{HEAD}/pullrequests", { "values" => [ { "id" => 42, "title" => "Pool", "author" => { "display_name" => "Ana" },
                                                                        "links" => { "html" => { "href" => "https://bitbucket.org/acme/web/pull-requests/42" } } } ] })
        get("#{REPO}/pullrequests/42", { "participants" => [ { "approved" => true, "user" => { "display_name" => "Cy" } } ] })
        text_at("#{REPO}/src/#{HEAD}/.bitbucket/CODEOWNERS", "app/ @platform\n")

        text = call(:compare_commits, "repo" => "acme/web", "base" => BASE, "head" => HEAD)

        assert_match "1 commits, 2 files changed. Base #{BASE}, head #{HEAD}.", text
        assert text.index("db/migrate/1_pool.rb (added") < text.index("app/pool.rb (modified")
        assert_match "PR #42 Pool by Ana, approved by Cy https://bitbucket.org/acme/web/pull-requests/42", text
        assert_match "@platform: app/pool.rb", text
        assert_match "Diffs, at https://bitbucket.org/acme/web/commits/#{HEAD}:", text
        assert_match "app/pool.rb\ndiff --git a/app/pool.rb", text
      end

      test "a file is read at the commit its ref names and linked there, and a secret is never read" do
        get(REPO, { "mainbranch" => { "name" => "main" } })
        get("#{REPO}/commits/main", { "values" => [ { "hash" => HEAD } ] })
        text_at("#{REPO}/src/#{HEAD}/app/pool.rb", "a\nb\nc\n")

        text = body(call(:fetch_file, "repo" => "acme/web", "path" => "app/pool.rb", "start_line" => 2))

        assert_match "app/pool.rb:1-3 (of 3 lines) at the main branch, commit #{HEAD[0, 12]}", text
        assert_match "   2  b", text
        assert text.end_with?("https://bitbucket.org/acme/web/commits/#{HEAD}"), "a file has no page in Bitbucket's API, so it links the commit it was read at"
        assert_raises(NativePack::Error) { call(:fetch_file, "repo" => "acme/web", "path" => ".env") }
      end

      test "blame runs git in the sandbox, since Bitbucket's API has none, and names the pull request" do
        porcelain = "#{HEAD} 10 10 2\nauthor Ana\nauthor-time 1790000000\nsummary Raise the pool\nfilename app/pool.rb\n\tline\n" \
                    "#{HEAD} 11 11\n\tline\n#{BASE} 5 12 1\nauthor Bo\nauthor-time 1780000000\nsummary First pool\nfilename app/pool.rb\n\tline\n"
        CodeReading.any_instance.expects(:exec).with do |repo, **options|
          repo == "acme/web" && options[:where] == Sandboxes::Client::IN_GIT &&
            options[:argv] == [ "blame", "--porcelain", "-L", "10,12", Sandboxes::Client::COMMIT, "--", "app/pool.rb" ]
        end.returns("stdout" => porcelain, "exit_code" => 0, "commit" => HEAD)
        get("#{REPO}/commit/#{HEAD}/pullrequests", { "values" => [ { "id" => 42, "title" => "Pool", "links" => { "html" => { "href" => "https://bitbucket.org/acme/web/pull-requests/42" } } } ] })
        get("#{REPO}/commit/#{BASE}/pullrequests", { "values" => [] })

        text = body(call(:blame, "repo" => "acme/web", "path" => "app/pool.rb", "start_line" => 10, "end_line" => 12))

        assert_match "L10-11       #{HEAD[0, 12]} #{Time.zone.at(1_790_000_000).utc.iso8601} Raise the pool (Ana)", text
        assert_match "L12-12       #{BASE[0, 12]}", text
        assert_match "Pull requests: #42 Pool https://bitbucket.org/acme/web/pull-requests/42.", text
      end

      test "the sandbox fetches from bitbucket.org as Bitbucket documents for a token, never following a redirect" do
        remote = @pack.send(:code_remote, @row)

        assert_equal [ "https://bitbucket.org/acme/web.git", "x-token-auth", "bb-token", [ "http.followRedirects=false" ] ],
                     [ remote.url("acme/web"), remote.user, remote.token.call, remote.options ]
        assert_equal "bitbucket.org:acme/web", remote.key("acme/web")
      end

      test "pipelines are newest first, filtered as asked, without a page Bitbucket does not give" do
        BitbucketApi.any_instance.expects(:get).with("#{REPO}/pipelines", { "sort" => "-created_on", "target.branch" => "main", "status" => "FAILED", "pagelen" => 5 })
                    .returns("values" => [ pipeline(7, "FAILED") ])

        text = body(call(:pipelines, "repo" => "acme/web", "branch" => "main", "status" => "FAILED", "limit" => 5))

        assert_match "pipeline 7 #{PIPELINE}  failed  main  #{HEAD[0, 12]}  push by Ana", text
        assert_no_match "pipelines/results", text
        assert_raises(NativePack::Error) { call(:pipelines, "repo" => "acme/web", "status" => "BROKEN") }
      end

      test "a pipeline's steps say how each ended, linked to the commit it built" do
        get("#{REPO}/pipelines/#{ERB::Util.url_encode(PIPELINE)}", pipeline(7, "FAILED"))
        list("#{REPO}/pipelines/#{PIPELINE}/steps", [ step("Build", "SUCCESSFUL"), step("Test", "FAILED") ])

        text = body(call(:pipeline_steps, "repo" => "acme/web", "pipeline" => PIPELINE.delete("{}")))

        assert_match "Pipeline 7 in acme/web, failed, on main", text
        assert_match "Test  failed  42s  step #{STEP}", text
        assert text.end_with?("https://bitbucket.org/acme/web/commits/#{HEAD}")
      end

      test "without a step the log is the newest failed step's, its end filtered as asked" do
        BitbucketApi.any_instance.stubs(:get).with("#{REPO}/pipelines", { "sort" => "-created_on", "target.branch" => nil, "status" => "FAILED", "pagelen" => 30 })
                    .returns("values" => [ pipeline(7, "FAILED") ])
        list("#{REPO}/pipelines/#{PIPELINE}/steps", [ step("Build", "SUCCESSFUL"), step("Test", "FAILED") ])
        text_at("#{REPO}/pipelines/#{PIPELINE}/steps/#{STEP}/log", "\e[32mbundle\e[0m\nrspec\nPG::ConnectionBad\nexit 1\n")

        text = body(call(:job_log, "repo" => "acme/web", "text" => "PG"))

        assert_match "Step Test of pipeline 7 in acme/web, failed, on main", text
        assert_match "Its log, 1 lines:\nPG::ConnectionBad", text
        assert text.end_with?("https://bitbucket.org/acme/web/commits/#{HEAD}")
      end

      test "no failed step is said, with where it looked" do
        BitbucketApi.any_instance.stubs(:get).with("#{REPO}/pipelines", { "sort" => "-created_on", "target.branch" => "main", "status" => "FAILED", "pagelen" => 30 })
                    .returns("values" => [])

        assert_equal "No failed pipeline step in acme/web on main among its newest 30 failed pipelines.", call(:job_log, "repo" => "acme/web", "branch" => "main")
      end

      test "a named step's log is read from its pipeline" do
        get("#{REPO}/pipelines/#{ERB::Util.url_encode(PIPELINE)}", pipeline(7, "FAILED"))
        get("#{REPO}/pipelines/#{PIPELINE}/steps/#{ERB::Util.url_encode(STEP)}", step("Test", "FAILED"))
        BitbucketApi.any_instance.stubs(:text).raises(BitbucketApi::NotFound, "Bitbucket answered 404")

        text = body(call(:job_log, "repo" => "acme/web", "pipeline" => PIPELINE, "step" => STEP))

        assert_match "Bitbucket keeps no log for this step, or no longer keeps it.", text
      end

      test "the CI status names the failing steps, since when it fails, and what each environment last deployed" do
        get(REPO, { "mainbranch" => { "name" => "main" } })
        BitbucketApi.any_instance.stubs(:get).with("#{REPO}/pipelines", { "sort" => "-created_on", "target.branch" => "main", "pagelen" => 10 })
                    .returns("values" => [ pipeline(7, "FAILED"), pipeline(6, "FAILED"), pipeline(5, "SUCCESSFUL") ])
        list("#{REPO}/pipelines/#{PIPELINE}/steps", [ step("Test", "FAILED") ])
        deployments

        text = body(call(:ci_status, "repo" => "acme/web"))

        assert_match "Latest pipeline on main: 7 (#{PIPELINE}), failed", text
        assert_match "Failed steps:\n  Test  failed", text
        assert_match "failed, failed, successful. It last passed in pipeline 5", text
        assert_match "Environments, what each last deployed:\n  Production:", text
      end

      test "a finished pipeline runs again as a new pipeline on the same target and definition, with its plain variables" do
        get("#{REPO}/pipelines/#{ERB::Util.url_encode(PIPELINE)}", pipeline(7, "FAILED").merge(
          "target" => { "type" => "pipeline_ref_target", "ref_type" => "branch", "ref_name" => "main", "commit" => { "type" => "commit", "hash" => HEAD, "links" => {} },
                        "selector" => { "type" => "custom", "pattern" => "smoke" } },
          "variables" => [ { "uuid" => "{v}", "key" => "REGION", "value" => "eu", "secured" => false } ]
        ))
        BitbucketApi.any_instance.expects(:post).with("#{REPO}/pipelines/", {
          "target" => { "type" => "pipeline_ref_target", "ref_type" => "branch", "ref_name" => "main", "commit" => { "type" => "commit", "hash" => HEAD },
                        "selector" => { "type" => "custom", "pattern" => "smoke" } },
          "variables" => [ { "key" => "REGION", "value" => "eu" } ]
        }).returns(pipeline(8, nil).merge("uuid" => "{new}"))

        text = body(call(:rerun_pipeline, "repo" => "acme/web", "pipeline" => PIPELINE))

        assert_match "Started pipeline 8 ({new}) in acme/web, running pipeline 7 again on main at #{HEAD[0, 12]}, every step from the start. " \
                     "pipeline_steps with its uuid, or ci_status, follows it.", text
        assert text.end_with?("https://bitbucket.org/acme/web/commits/#{HEAD}")
      end

      test "a pull request's pipeline runs again on the same pull request" do
        get("#{REPO}/pipelines/#{ERB::Util.url_encode(PIPELINE)}", pipeline(7, "FAILED").merge(
          "target" => { "type" => "pipeline_pullrequest_target", "source" => "fix", "destination" => "main", "destination_commit" => { "hash" => BASE, "type" => "commit" },
                        "commit" => { "type" => "commit", "hash" => HEAD }, "pullrequest" => { "id" => 3, "title" => "Fix" }, "selector" => { "type" => "pull-requests", "pattern" => "**" } }
        ))
        BitbucketApi.any_instance.expects(:post).with("#{REPO}/pipelines/", {
          "target" => { "type" => "pipeline_pullrequest_target", "source" => "fix", "destination" => "main", "commit" => { "type" => "commit", "hash" => HEAD },
                        "destination_commit" => { "hash" => BASE }, "pullrequest" => { "id" => "3" }, "selector" => { "type" => "pull-requests", "pattern" => "**" } }
        }).returns(pipeline(8, nil))

        assert_match "Started pipeline 8", body(call(:rerun_pipeline, "repo" => "acme/web", "pipeline" => PIPELINE))
      end

      test "a pipeline still going, or one given secured variables, is not run again" do
        BitbucketApi.any_instance.expects(:post).never
        get("#{REPO}/pipelines/#{ERB::Util.url_encode(PIPELINE)}", pipeline(7, nil).merge("state" => { "name" => "IN_PROGRESS", "stage" => { "name" => "RUNNING" } }))
        assert_equal "Pipeline 7 in acme/web is still running, so it cannot run again until it finishes. cancel_pipeline stops it.",
                     assert_raises(NativePack::Error) { call(:rerun_pipeline, "repo" => "acme/web", "pipeline" => PIPELINE) }.message

        get("#{REPO}/pipelines/#{ERB::Util.url_encode(PIPELINE)}", pipeline(7, "FAILED").merge("variables" => [ { "key" => "TOKEN", "value" => "", "secured" => true } ]))
        assert_match "was given secured variables, which Bitbucket never hands back", assert_raises(NativePack::Error) { call(:rerun_pipeline, "repo" => "acme/web", "pipeline" => PIPELINE) }.message
      end

      test "a pipeline runs on the main branch unless a branch or tag is named, a custom one by name, with variables" do
        get(REPO, { "mainbranch" => { "name" => "main" } })
        BitbucketApi.any_instance.expects(:post).with("#{REPO}/pipelines/", {
          "target" => { "type" => "pipeline_ref_target", "ref_type" => "branch", "ref_name" => "main", "selector" => { "type" => "custom", "pattern" => "deploy-staging" } },
          "variables" => [ { "key" => "REGION", "value" => "eu" } ]
        }).returns(pipeline(9, nil))

        text = body(call(:run_pipeline, "repo" => "acme/web", "custom" => "deploy-staging", "variables" => { "REGION" => "eu" }))

        assert_match "Started pipeline 9 (#{PIPELINE}) on main in acme/web, the custom pipeline deploy-staging with REGION.", text

        BitbucketApi.any_instance.expects(:post).with("#{REPO}/pipelines/", { "target" => { "type" => "pipeline_ref_target", "ref_type" => "tag", "ref_name" => "v1.2.0" } })
                    .returns(pipeline(10, nil))
        assert_match "on v1.2.0 in acme/web, the pipeline that matches it.", body(call(:run_pipeline, "repo" => "acme/web", "ref" => "v1.2.0", "ref_type" => "tag"))
        BitbucketApi.any_instance.expects(:post).returns(pipeline(11, nil).merge("target" => { "ref_name" => "main" }))
        assert_match "had not named the commit it builds yet, so there is no link.", body(call(:run_pipeline, "repo" => "acme/web"))
        assert_equal "ref_type must be one of branch, tag", assert_raises(NativePack::Error) { call(:run_pipeline, "repo" => "acme/web", "ref_type" => "bookmark") }.message
      end

      test "a running pipeline is stopped, and a finished one is said to have nothing to stop" do
        get("#{REPO}/pipelines/#{ERB::Util.url_encode(PIPELINE)}", pipeline(7, nil).merge("state" => { "name" => "IN_PROGRESS", "stage" => { "name" => "RUNNING" } }))
        BitbucketApi.any_instance.expects(:post).with("#{REPO}/pipelines/#{ERB::Util.url_encode(PIPELINE)}/stopPipeline").returns({})

        assert_match "Stopping pipeline 7 in acme/web, on main at #{HEAD[0, 12]}, and every step that has not finished.", body(call(:cancel_pipeline, "repo" => "acme/web", "pipeline" => PIPELINE))

        get("#{REPO}/pipelines/#{ERB::Util.url_encode(PIPELINE)}", pipeline(7, "SUCCESSFUL"))
        assert_equal "Pipeline 7 in acme/web already finished, successful, so there is nothing to stop.",
                     assert_raises(NativePack::Error) { call(:cancel_pipeline, "repo" => "acme/web", "pipeline" => PIPELINE) }.message
      end

      test "Bitbucket refusing a change is said with the scope it needs" do
        get(REPO, { "mainbranch" => { "name" => "main" } })
        BitbucketApi.any_instance.stubs(:post).raises(BitbucketApi::Refused, "Bitbucket answered 403: Your credentials lack one or more required privilege scopes.")

        assert_equal "Bitbucket refused to run a pipeline on main in acme/web: Bitbucket answered 403: Your credentials lack one or more required privilege scopes. " \
                     "Running or stopping a pipeline needs a token that can write pipelines, the write:pipeline:bitbucket scope.",
                     assert_raises(NativePack::Error) { call(:run_pipeline, "repo" => "acme/web") }.message
      end

      test "the map holds the workspace's repositories and the infrastructure defined in them" do
        list("/repositories/acme", [
          { "full_name" => "acme/web", "mainbranch" => { "name" => "main" }, "size" => 1000, "links" => { "html" => { "href" => "https://bitbucket.org/acme/web" } } },
          { "full_name" => "acme/fork", "mainbranch" => { "name" => "main" }, "size" => 10, "parent" => { "full_name" => "other/x" },
            "links" => { "html" => { "href" => "https://bitbucket.org/acme/fork" } } }
        ])
        get("#{REPO}/commits/main", { "values" => [ { "hash" => HEAD } ] })
        list("#{REPO}/src/#{HEAD}/", [
          { "type" => "commit_directory", "path" => "infra" }, { "type" => "commit_file", "path" => "infra/dns.tf", "size" => 100 },
          { "type" => "commit_file", "path" => "infra/big.tf", "size" => 900_000 }, { "type" => "commit_file", "path" => "app/pool.rb", "size" => 10 }
        ])
        text_at("#{REPO}/src/#{HEAD}/infra/dns.tf", %(resource "cloudflare_record" "app" { name = "app.acme.com" }))

        snapshot = @pack.map_of(@row)

        assert_equal [ [ "bitbucket", "acme", "repository", "acme/web", "https://bitbucket.org/acme/web" ] ],
                     snapshot.resources.first(1).map { |found| [ found.provider, found.account, found.kind, found.external_id, found.url ] }
        assert_equal [ [ "acme/web", "infra/dns.tf", "Terraform", "bitbucket", "https://bitbucket.org/acme/web" ] ],
                     snapshot.code_files.map { |file| [ file.repository, file.path, file.tool, file.provider, file.url ] }
        assert_match "over 200 KB", snapshot.gaps.map(&:text).join
        assert_empty snapshot.code_read
      end

      test "a change re-reads one repository with its infrastructure files, a push only when it moved the main branch, and only Bitbucket's not found takes it away" do
        get(REPO, { "full_name" => "acme/web", "mainbranch" => { "name" => "main" }, "size" => 1000, "links" => { "html" => { "href" => "https://bitbucket.org/acme/web" } } })
        get("#{REPO}/commits/main", { "values" => [ { "hash" => HEAD } ] })
        list("#{REPO}/src/#{HEAD}/", [ { "type" => "commit_file", "path" => "infra/dns.tf", "size" => 100 } ])
        text_at("#{REPO}/src/#{HEAD}/infra/dns.tf", %(resource "cloudflare_record" "app" {}))
        repository = ResourceMap::Scope.new(account: "acme", kind: ResourceMap::KIND_REPOSITORY, external_id: "acme/web")

        snapshot = @pack.map_refresh(@row, repository)
        assert_equal [ [ "bitbucket", "acme", ResourceMap::KIND_REPOSITORY, "acme/web" ] ], snapshot.resources.map(&:key)
        assert_equal [ "infra/dns.tf" ], snapshot.code_files.map(&:path)
        assert_equal [ "acme/web" ], snapshot.code_read

        main = @pack.map_refresh(@row, ResourceMap::Scope.new(account: "acme", kind: ResourceMap::KIND_BRANCH, external_id: "acme/web/main"))
        assert_equal [ "acme/web" ], main.resources.map(&:external_id)
        feature = @pack.map_refresh(@row, ResourceMap::Scope.new(account: "acme", kind: ResourceMap::KIND_BRANCH, external_id: "acme/web/feature/main"))
        assert_empty feature.resources, "a push to another branch changes nothing the map reads"
        assert_empty feature.code_files

        BitbucketApi.any_instance.stubs(:get).with { |called, *| called == "/repositories/acme/gone" }.raises(BitbucketApi::NotFound, "Bitbucket answered 404: Repository not found")
        assert_equal [ [ "bitbucket", "acme", ResourceMap::KIND_REPOSITORY, "acme/gone" ] ], @pack.map_refresh(@row, repository.with(external_id: "acme/gone")).gone
        assert_nil @pack.map_refresh(@row, ResourceMap::Scope.new(account: "acme")), "a workspace is read by a sweep"
      end

      private

      def call(tool, arguments = {}) = @pack.call(tool.to_s, environment_row: @row, arguments: arguments)

      def body(result) = result.is_a?(Hash) ? result["content"].map { |part| part["text"] }.join("\n") : result

      def get(path, answer) = BitbucketApi.any_instance.stubs(:get).with { |called, *| called == path }.returns(answer)

      def list(path, items, more: false) = BitbucketApi.any_instance.stubs(:list).with { |called, *| called == path }.returns([ items, more ])

      def text_at(path, text) = BitbucketApi.any_instance.stubs(:text).with { |called, *| called == path }.returns(text)

      def stat(path, added, removed, status = "modified")
        { "status" => status, "lines_added" => added, "lines_removed" => removed, "new" => { "path" => path }, "old" => (status == "added" ? nil : { "path" => path }) }
      end

      def pipeline(number, result)
        { "uuid" => PIPELINE, "build_number" => number, "created_on" => "2026-10-02T10:0#{number}:00Z", "completed_on" => "2026-10-02T10:1#{number}:00Z",
          "state" => { "name" => "COMPLETED", "result" => { "name" => result } }, "trigger" => { "name" => "PUSH" }, "creator" => { "display_name" => "Ana" },
          "target" => { "ref_name" => "main", "commit" => { "hash" => HEAD } } }
      end

      def step(name, result)
        { "uuid" => STEP, "name" => name, "duration_in_seconds" => 42, "completed_on" => "2026-10-02T10:20:00Z",
          "state" => { "name" => "COMPLETED", "result" => { "name" => result } } }
      end

      def deployment(uuid, environment, hash, completed, status = "SUCCESSFUL")
        { "uuid" => uuid, "environment" => { "uuid" => environment },
          "release" => { "name" => "7", "url" => "https://bitbucket.org/acme/web/pipelines/results/7", "commit" => { "hash" => hash } },
          "state" => { "name" => "COMPLETED", "status" => { "name" => status }, "completion_date" => completed, "deployer" => { "display_name" => "Ana" } } }
      end

      def deployments
        list("#{REPO}/environments", [ { "uuid" => "{prod}", "name" => "Production" }, { "uuid" => "{stage}", "name" => "Staging" } ])
        list("#{REPO}/deployments", [
          deployment("{d1}", "{prod}", BASE, "2026-10-01T10:00:00Z"),
          deployment("{d3}", "{stage}", HEAD, "2026-10-02T11:00:00Z"),
          deployment("{d2}", "{prod}", HEAD, "2026-10-02T11:30:00Z")
        ])
      end
    end
  end
end

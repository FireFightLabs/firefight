require "test_helper"

module Integrations
  module Packs
    class AzureDevopsTest < ActiveSupport::TestCase
      REPO = "/Shop/_apis/git/repositories/checkout".freeze
      BUILDS = "/Shop/_apis/build/builds".freeze
      SHA = ("a" * 40).freeze
      WEB = "https://dev.azure.com/fabrikam/Shop/_git/checkout".freeze
      PROJECT_WEB = "https://dev.azure.com/fabrikam/Shop".freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "azure_devops", name: "Azure DevOps")
        @row = @integration.integration_environments.create!
        @row.store_fields!(AzureDevops::ORGANIZATION => "fabrikam", AzureDevops::PROJECT => %w[Shop])
        AzureDevops.store_credentials!(@row, AzureDevops::TOKEN => " pat-token ")
        @pack = AzureDevops.new(@integration, box_key: "investigation-1")
        AzureDevopsApi.any_instance.stubs(:get).with(REPO).returns(repository)
        AzureDevopsApi.any_instance.stubs(:get).with("/_apis/projects/Shop").returns("id" => "project-guid", "name" => "Shop", "_links" => { "web" => { "href" => PROJECT_WEB } })
      end

      test "the token is the one credential, the organization and projects connect fields, and only the test runner and CI changes write" do
        assert_equal "pat-token", ConnectionSettings.of(@row.reload).credential(AzureDevops::TOKEN)
        assert_equal [ AzureDevops::TOKEN ], AzureDevops.credential_fields.map(&:key)
        assert_equal %w[run_tests run_pipeline retry_pipeline cancel_pipeline approve_check], AzureDevops.tool_definitions.reject(&:read_only).map(&:name)
        organization, project = IntegrationProvider.find(AzureDevops::PROVIDER_KEY).connect_fields
        assert_equal [ AzureDevops::ORGANIZATION, false ], [ organization.key, organization.scope ]
        assert_nil organization.refusal("fabrikam")
        assert organization.refusal("fabrikam/Shop").present?
        assert_equal [ AzureDevops::PROJECT, true ], [ project.key, project.scope ]
      end

      test "a token is checked with Azure DevOps before anything is saved, for each project chosen or every one it can read" do
        assert_equal "Paste a personal access token.", AzureDevops.credential_refusal({ AzureDevops::TOKEN => " " }, fields: { "organization" => "fabrikam", "project" => %w[Shop] })
        assert_equal "Choose at least one project, or all the token can read.", AzureDevops.credential_refusal({ AzureDevops::TOKEN => "t" }, fields: { "organization" => "fabrikam" })

        AzureDevopsApi.any_instance.stubs(:get).with("/_apis/projects/Shop").raises(AzureDevopsApi::Refused, "Azure DevOps answered 401: TF400813")
        assert_match "Azure DevOps refused this token: Azure DevOps answered 401: TF400813. Check it is active",
                     AzureDevops.credential_refusal({ AzureDevops::TOKEN => "t" }, fields: { "organization" => "fabrikam", "project" => %w[Shop] })

        AzureDevopsApi.any_instance.stubs(:get).with("/_apis/projects/Shop").raises(AzureDevopsApi::NotFound, "Azure DevOps answered 404")
        assert_equal "Azure DevOps has no project Shop in this organization that this token can see.",
                     AzureDevops.credential_refusal({ AzureDevops::TOKEN => "t" }, fields: { "organization" => "fabrikam", "project" => %w[Shop] })

        AzureDevopsApi.any_instance.stubs(:list).with("/_apis/projects", { "$top" => 100 }, pages: AzureDevops::MAX_PROJECT_PAGES).returns([ [ { "name" => "Shop" } ], false ])
        assert_nil AzureDevops.credential_refusal({ AzureDevops::TOKEN => "t" }, fields: { "organization" => "fabrikam", "project" => [ IntegrationProvider::ConnectField::ALL ] })
        assert_equal [ "Shop" ], AzureDevops.scope_options({ AzureDevops::TOKEN => "t" }, fields: { "organization" => "fabrikam" }).map(&:value)
      end

      test "a pull request says who wrote it, how each reviewer voted, its files, and links to its page" do
        stub_get("#{REPO}/pullrequests/42", "pullRequestId" => 42, "title" => "Raise pool size", "status" => "completed", "closedDate" => "2026-10-01T10:00:00Z",
                                            "closedBy" => { "displayName" => "Ana" }, "createdBy" => { "displayName" => "Uros" }, "sourceRefName" => "refs/heads/pool",
                                            "targetRefName" => "refs/heads/main", "lastMergeCommit" => { "commitId" => SHA }, "description" => "Pool ran dry.",
                                            "reviewers" => [ { "displayName" => "Lea", "vote" => 10, "isRequired" => true }, { "displayName" => "Max", "vote" => -5 } ])
        stub_get("#{REPO}/pullRequests/42/iterations", "value" => [ { "id" => 1 }, { "id" => 2 } ])
        stub_get("#{REPO}/pullRequests/42/iterations/2/changes", { "$top" => 2000, "$skip" => 0 },
                 "changeEntries" => [ { "item" => { "path" => "/config/database.yml" }, "changeType" => "edit" }, { "item" => { "path" => "/config", "isFolder" => true }, "changeType" => "edit" } ],
                 "nextSkip" => 0)

        text = call(:pr_lookup, "repo" => "Shop/checkout", "id" => 42)

        assert_includes text, "PR !42: Raise pool size"
        assert_includes text, "completed at 2026-10-01T10:00:00Z by Ana"
        assert_includes text, "Reviewers: Lea approved (required), Max waiting for author"
        assert_includes text, "config/database.yml (modified)"
        assert_not_includes text, "  config (", "a folder is not a file"
        assert text.end_with?("#{WEB}/pullrequest/42")
      end

      test "a repository is project/repository, and a commit a SHA, branch or tag read as the commit it points at" do
        assert_match "project/repository", assert_raises(NativePack::Error) { call(:commit_lookup, "repo" => "../etc", "sha" => "abc") }.message

        stub_get("#{REPO}/refs", { "filter" => "heads/main", "peelTags" => true }, "value" => [ { "name" => "refs/heads/main", "objectId" => SHA } ])
        stub_get("#{REPO}/commits/#{SHA}", { "changeCount" => AzureDevops::COMPARE_CHANGES },
                 "commitId" => SHA, "author" => { "name" => "Ana", "date" => "2026-10-01T09:00:00Z" }, "comment" => "Raise pool",
                 "remoteUrl" => "#{WEB}/commit/#{SHA}", "changes" => [ { "item" => { "path" => "/config/database.yml" }, "changeType" => "edit" } ])

        text = call(:commit_lookup, "repo" => "Shop/checkout", "sha" => "main")

        assert_includes text, "Commit #{SHA}\nAuthor: Ana at 2026-10-01T09:00:00Z"
        assert_includes text, "config/database.yml (modified)"
        assert text.end_with?("#{WEB}/commit/#{SHA}")
      end

      test "completed pull requests are the newest completed first, each with its page" do
        stub_get("#{REPO}/pullrequests", { "searchCriteria.status" => "completed", "searchCriteria.queryTimeRangeType" => "closed",
                                            "searchCriteria.minTime" => nil, "$top" => AzureDevops::MERGED_CANDIDATES },
                 "value" => [ { "pullRequestId" => 1, "title" => "Old", "closedDate" => "2026-09-01T10:00:00Z", "targetRefName" => "refs/heads/main" },
                              { "pullRequestId" => 2, "title" => "New", "closedDate" => "2026-10-01T10:00:00Z", "closedBy" => { "displayName" => "Ana" },
                                "targetRefName" => "refs/heads/main" } ])

        assert_equal [ "PR !2  New  completed 2026-10-01T10:00:00Z by Ana into main  #{WEB}/pullrequest/2",
                       "PR !1  Old  completed 2026-09-01T10:00:00Z by unknown into main  #{WEB}/pullrequest/1" ],
                     call(:merged_pull_requests, "repo" => "Shop/checkout").lines.map(&:chomp)
      end

      test "a comparison takes the changed files from Azure DevOps and the commits and diffs from git, and names the pull requests that merged them" do
        head = "c" * 40
        stub_get("#{REPO}/refs", { "filter" => "heads/main" }, "value" => [ { "name" => "refs/heads/main" } ])
        stub_get("#{REPO}/diffs/commits", { "baseVersion" => SHA, "baseVersionType" => "commit", "targetVersion" => "main", "targetVersionType" => "branch",
                                             "diffCommonCommit" => false, "$top" => AzureDevops::COMPARE_CHANGES },
                 "allChangesIncluded" => true, "baseCommit" => SHA, "targetCommit" => head, "aheadCount" => 1,
                 "changes" => [ { "item" => { "path" => "/db/migrate/1_add.rb" }, "changeType" => "add" }, { "item" => { "path" => "/.env" }, "changeType" => "edit" } ])
        CodeReading.any_instance.expects(:exec).with("Shop/checkout", ref: "main", where: Sandboxes::Client::IN_GIT,
                                                     argv: [ "log", "--format=%H%x09%an%x09%aI%x09%s", Sandboxes::Client::COMMIT, "^#{SHA}" ])
                   .returns("exit_code" => 0, "stdout" => "#{head}\tAna\t2026-10-01T09:00:00Z\tAdd column\n")
        CodeReading.any_instance.expects(:exec).with("Shop/checkout", ref: "main", where: Sandboxes::Client::IN_GIT,
                                                     argv: [ "diff", "--patch", "--end-of-options", SHA, Sandboxes::Client::COMMIT ])
                   .returns("exit_code" => 0, "stdout" => "diff --git a/db/migrate/1_add.rb b/db/migrate/1_add.rb\n+add_column\ndiff --git a/.env b/.env\n+SECRET=x\n")
        AzureDevopsApi.any_instance.expects(:post).with("#{REPO}/pullrequestquery", { "queries" => [ { "type" => "commit", "items" => [ head ] } ] })
                      .returns("results" => [ { head => [ { "pullRequestId" => 5, "title" => "Add column", "createdBy" => { "displayName" => "Ana" },
                                                            "reviewers" => [ { "displayName" => "Lea", "vote" => 10 } ] } ] } ])

        result = @pack.compare_commits(environment_row: @row, arguments: { "repo" => "Shop/checkout", "base" => SHA, "head" => "main" })
        text = result.dig("content", 0, "text")

        assert_includes text, "1 commits, 2 files changed."
        assert_includes text, "db/migrate/1_add.rb (added, +1 -0)"
        assert_includes text, "PR !5 Add column by Ana, approved by Lea #{WEB}/pullrequest/5"
        assert_includes text, "(not shown, since the file may hold secrets)"
        assert_not_includes text, "SECRET=x"
        range = Capabilities::Comparison.of(result)
        assert_equal [ 1, [ "db/migrate/1_add.rb" ], true, "#{WEB}/commit/#{head}" ], [ range.commits, range.migrations, range.complete, range.link ]
      end

      test "a repository's setup is the job with services from azure-pipelines.yml, its containers, variables and script lines" do
        yaml = <<~YAML
          variables:
            RAILS_ENV: test
            DATABASE_URL: postgres://postgres:secret@postgres:5432/app_$(RAILS_ENV)
          resources:
            containers:
              - container: pg
                image: postgres:16
                env:
                  POSTGRES_PASSWORD: secret
          stages:
            - stage: Test
              jobs:
                - job: lint
                  steps:
                    - script: bundle exec rubocop
                - job: tests
                  services:
                    postgres: pg
                  steps:
                    - script: |
                        bin/rails db:schema:load
                        bin/rails test
          YAML
        stub_get("#{REPO}/items", { "path" => "/azure-pipelines.yml", "includeContent" => true, "$format" => "json" }, "content" => yaml)

        found = @pack.ci_setup(@row, repository: "Shop/checkout")

        assert_equal "azure-pipelines.yml, job tests", found.source
        assert_equal [ "postgres:16" ], found.services.map { |service| service["image"] }
        assert_includes found.commands, "bin/rails db:schema:load"
        assert_equal "test", found.env["RAILS_ENV"]
      end

      test "CI runs are a repository's runs newest first, each with how long it took, and a run that partly succeeded counts as finished" do
        stub_get(BUILDS, { "repositoryId" => "repo-guid", "repositoryType" => "TfsGit", "$top" => 10, "queryOrder" => "queueTimeDescending" },
                 "value" => [ build(2, "inProgress", nil, start: "2026-10-01T11:00:00Z"),
                              build(1, "completed", "partiallySucceeded", start: "2026-10-01T10:00:00Z", finish: "2026-10-01T10:05:00Z") ])

        result = @pack.ci_runs(environment_row: @row, arguments: { "repo" => "Shop/checkout" })
        running, done = Capabilities::History.runs_of(result)

        assert_equal [ "2", Capabilities::History::RUNNING, nil ], [ running.id, running.status, running.finished_at ]
        assert_equal [ Capabilities::History::SUCCEEDED, 300 ], [ done.status, done.seconds ]
        assert_includes done.detail, "partly succeeded"
      end

      test "one run read by its id carries its jobs, a failed one with its error and how its log is read, and a skipped job left out" do
        stub_get("#{BUILDS}/7", build(7, "inProgress", nil, start: "2026-10-01T10:00:00Z"))
        stub_get("#{BUILDS}/7/timeline", "records" => timeline_records)

        run = Capabilities::History.runs_of(@pack.ci_runs(environment_row: @row, arguments: { "repo" => "Shop/checkout", "run" => "7" })).sole

        assert_equal [ "Build / Compile", "Build / Test" ], run.parts.map(&:name)
        test_job = run.parts.last
        assert_equal [ Capabilities::History::FAILED, "Tests failed" ], [ test_job.status, test_job.detail ]
        assert_equal({ "tool" => "job_log", "arguments" => { "project" => "Shop", "build_id" => 7, "log_id" => 5 } }, test_job.log)
      end

      test "a run of another repository is refused rather than read as this one's" do
        stub_get("#{BUILDS}/8", build(8, "completed", "failed").merge("repository" => { "id" => "other-guid", "name" => "web" }))

        assert_match "built web, not Shop/checkout", assert_raises(NativePack::Error) { call(:ci_runs, "repo" => "Shop/checkout", "run" => "8") }.message
      end

      test "a job's log is the failed step's, read as text and filtered as asked" do
        stub_get("#{BUILDS}/7", build(7, "completed", "failed", start: "2026-10-01T10:00:00Z", finish: "2026-10-01T10:05:00Z"))
        stub_get("#{BUILDS}/7/timeline", "records" => timeline_records)
        AzureDevopsApi.any_instance.expects(:text).with("#{BUILDS}/7/logs/6").returns("2026-10-01T10:04:00Z starting\n2026-10-01T10:04:30Z ##[error]Tests failed\n")

        text = call(:job_log, "project" => "Shop", "build_id" => 7, "text" => "error")

        assert_includes text, "Run 20261001.7 (7) of checkout-ci in Shop, failed, on main"
        assert_includes text, "Step: Build / Test / Run tests."
        assert_includes text, "##[error]Tests failed"
        assert_not_includes text, "starting"
      end

      test "CI status names the latest run's failed jobs, when the branch last passed, approvals waiting and what each environment received" do
        stub_get(BUILDS, { "repositoryId" => "repo-guid", "repositoryType" => "TfsGit", "$top" => 10, "queryOrder" => "queueTimeDescending", "branchName" => "refs/heads/main" },
                 "value" => [ build(7, "completed", "failed"), build(6, "completed", "succeeded") ])
        stub_get("#{BUILDS}/7/timeline", "records" => timeline_records)
        stub_get("/Shop/_apis/pipelines/approvals", { "state" => "pending", "$expand" => "steps", "top" => 50 },
                 "value" => [ { "id" => "aab27959-a5be-4ee3-97ca-f19b3602cd2f", "createdOn" => "2026-10-01T10:06:00Z", "minRequiredApprovers" => 1,
                                "steps" => [ { "assignedApprover" => { "displayName" => "Lea" } } ] } ])
        stub_get("/Shop/_apis/distributedtask/environments", { "$top" => 50 }, "value" => [ { "id" => 3, "name" => "production" } ])
        stub_get("/Shop/_apis/distributedtask/environments/3/environmentdeploymentrecords", { "top" => 1 },
                 "value" => [ { "result" => "succeeded", "owner" => { "id" => 6, "name" => "20261001.6" }, "definition" => { "name" => "checkout-ci" }, "startTime" => "2026-10-01T09:00:00Z" } ])

        text = call(:ci_status, "repo" => "Shop/checkout")

        assert_includes text, "Latest run on main: 20261001.7 (7) of checkout-ci, failed"
        assert_includes text, "Build / Test  failed"
        assert_includes text, "It last passed in run 20261001.6 (6)"
        assert_includes text, "aab27959-a5be-4ee3-97ca-f19b3602cd2f  waiting since 2026-10-01T10:06:00Z  1 of Lea must approve"
        assert_includes text, "production: succeeded run 20261001.6 of checkout-ci at 2026-10-01T09:00:00Z"
      end

      test "a finished run's failed jobs are rerun, and one that succeeded or still runs is left as it is" do
        stub_get("#{BUILDS}/6", build(6, "completed", "succeeded"))
        assert_match "has no failed jobs to rerun", assert_raises(NativePack::Error) { call(:retry_pipeline, "project" => "Shop", "build_id" => 6) }.message

        stub_get("#{BUILDS}/7", build(7, "completed", "failed"))
        AzureDevopsApi.any_instance.expects(:patch).with("#{BUILDS}/7", {}, { "retry" => true }).returns(build(7, "inProgress", nil))
        assert_match "Rerunning the failed jobs of run 20261001.7 (7) of checkout-ci in Shop, on main at #{SHA[0, 12]}. It is inProgress.",
                     call(:retry_pipeline, "project" => "Shop", "build_id" => 7)
      end

      test "a run still going is canceled by setting it cancelling, and a finished one has nothing to cancel" do
        stub_get("#{BUILDS}/6", build(6, "completed", "succeeded"))
        assert_match "already finished, succeeded", assert_raises(NativePack::Error) { call(:cancel_pipeline, "project" => "Shop", "build_id" => 6) }.message

        stub_get("#{BUILDS}/7", build(7, "inProgress", nil).merge("requestedFor" => { "displayName" => "Ana", "uniqueName" => "ana@example.com" }))
        AzureDevopsApi.any_instance.expects(:patch).with("#{BUILDS}/7", { "status" => "cancelling" }).returns({})
        assert_match "Canceling run 20261001.7 (7)", call(:cancel_pipeline, "project" => "Shop", "build_id" => 7)

        owner = @pack.owner_of("cancel_pipeline", environment_row: @row, arguments: { "project" => "Shop", "build_id" => 7 })
        assert_equal [ "Ana", "ana@example.com", Owner::ROLE_STARTED ], [ owner.name, owner.email, owner.role ]
      end

      test "a YAML pipeline runs through the Pipelines API on the ref asked, and a classic one is queued as a build" do
        stub_get("/Shop/_apis/build/definitions/12", "id" => 12, "name" => "checkout-ci", "process" => { "type" => 2 },
                                                      "repository" => { "id" => "repo-guid", "defaultBranch" => "refs/heads/main" })
        AzureDevopsApi.any_instance.expects(:post).with("/Shop/_apis/pipelines/12/runs",
                                                        { "resources" => { "repositories" => { "self" => { "refName" => "refs/heads/release" } } },
                                                          "variables" => { "DEPLOY" => { "value" => "true" } } }).returns("id" => 9)
        stub_get("#{BUILDS}/9", build(9, "notStarted", nil).merge("sourceBranch" => "refs/heads/release"))

        assert_match "Started run 20261001.9 (9) of Shop/checkout-ci on release with DEPLOY. It is notStarted.",
                     call(:run_pipeline, "pipeline" => "Shop/12", "ref" => "release", "variables" => { "DEPLOY" => "true" })

        stub_get("/Shop/_apis/build/definitions/13", "id" => 13, "name" => "legacy", "process" => { "type" => 1 }, "repository" => {})
        AzureDevopsApi.any_instance.expects(:post).with(BUILDS, { "definition" => { "id" => 13 } }).returns(build(10, "notStarted", nil))
        assert_match "Started run 20261001.10 (10) of Shop/legacy", call(:run_pipeline, "pipeline" => "Shop/13")
      end

      test "an approval is answered only while it waits, with the comment given" do
        id = "aab27959-a5be-4ee3-97ca-f19b3602cd2f"
        stub_get("/Shop/_apis/pipelines/approvals", { "approvalIds" => id, "$expand" => "steps" }, "value" => [ { "id" => id, "status" => "approved" } ])
        assert_match "is approved, so it is no longer waiting", assert_raises(NativePack::Error) { call(:approve_check, "project" => "Shop", "approval_id" => id, "decision" => "approve") }.message

        stub_get("/Shop/_apis/pipelines/approvals", { "approvalIds" => id, "$expand" => "steps" }, "value" => [ { "id" => id, "status" => "pending" } ])
        AzureDevopsApi.any_instance.expects(:patch).with("/Shop/_apis/pipelines/approvals", [ { "approvalId" => id, "status" => "rejected", "comment" => "Not now" } ])
                      .returns("value" => [ { "id" => id, "status" => "rejected" } ])
        assert_match "Answered approval #{id} in Shop: rejected. It is now rejected.",
                     call(:approve_check, "project" => "Shop", "approval_id" => id, "decision" => "reject", "comment" => "Not now")
      end

      test "deployments are what the environments recorded for the repository's runs, kept as data, another repository's left out" do
        stub_environments
        text = call(:recent_deployments, "repo" => "Shop/checkout")

        assert_includes text, "production  main  #{SHA[0, 12]}  succeeded  Deploy / Release  by Ana  run 20261001.7 (7) of checkout-ci"
        assert_not_includes text, "(8)"
        deploy = Capabilities::Deploys.deploys_of(@pack.recent_deployments(environment_row: @row, arguments: { "repo" => "Shop/checkout" })).sole
        assert_equal [ SHA, "main", Capabilities::History::SUCCEEDED, "production", "20261001.7" ], [ deploy.commit, deploy.branch, deploy.status, deploy.environment, deploy.version ]
      end

      test "the running commit is the last deployment that succeeded before the time, and without one a guess from the default branch" do
        stub_environments
        assert_includes call(:running_commit, "repo" => "Shop/checkout", "at" => "2026-10-01T12:00:00Z"), "Running in Shop/checkout at 2026-10-01T12:00:00Z: #{SHA}"

        stub_get("#{REPO}/commits", { "searchCriteria.itemVersion.version" => "main", "searchCriteria.itemVersion.versionType" => "branch",
                                       "searchCriteria.toDate" => "2026-10-01T09:00:00Z", "searchCriteria.$top" => 1 },
                 "value" => [ { "commitId" => "b" * 40, "committer" => { "date" => "2026-10-01T08:00:00Z" } } ])
        stub_get("#{REPO}/commits", { "searchCriteria.itemVersion.version" => "main", "searchCriteria.itemVersion.versionType" => "branch",
                                       "searchCriteria.toDate" => "2026-09-30T09:00:00Z", "searchCriteria.$top" => 1 }, "value" => [])
        text = call(:running_commit, "repo" => "Shop/checkout", "at" => "2026-10-01T09:00:00Z")
        assert_includes text, "not known. There is no successful deployment before then."
        assert_includes text, "Tip of main at that time: #{'b' * 40}"
      end

      test "classic release deployments are read on the Release API, kept as data with the release as their version" do
        stub_get("/Shop/_apis/release/deployments", { "$top" => 10, "queryOrder" => "descending" },
                 "value" => [ { "id" => 52, "release" => { "name" => "Release-14", "_links" => { "web" => { "href" => "https://dev.azure.com/fabrikam/Shop/_release?releaseId=14" } } },
                                "releaseDefinition" => { "name" => "MyShuttle.CD" }, "releaseEnvironment" => { "name" => "PROD" }, "deploymentStatus" => "succeeded",
                                "startedOn" => "2026-10-01T09:46:52Z", "completedOn" => "2026-10-01T09:48:17Z", "requestedFor" => { "displayName" => "Chuck" } } ])

        result = @pack.release_deployments(environment_row: @row, arguments: { "project" => "Shop" })

        assert_includes result.dig("content", 0, "text"), "MyShuttle.CD  Release-14  PROD  succeeded  by Chuck"
        assert_includes result.dig("content", 0, "text"), PROJECT_WEB, "the project's page is the one Projects - Get gives"
        deploy = Capabilities::Deploys.deploys_of(result).sole
        assert_equal [ "Release-14", "PROD", Capabilities::History::SUCCEEDED ], [ deploy.version, deploy.environment, deploy.status ]
      end

      test "the map holds the project's repositories and pipelines, each pipeline built from its repository, one on GitHub as GitHub puts it" do
        stub_get("/Shop/_apis/git/repositories", "value" => [ repository, repository.merge("name" => "old", "isDisabled" => true) ])
        AzureDevopsApi.any_instance.stubs(:list).with("/Shop/_apis/build/definitions", { "includeAllProperties" => true, "includeLatestBuilds" => true, "$top" => 100 },
                                                      pages: AzureDevops::MAX_DEFINITION_PAGES)
                      .returns([ [ { "id" => 12, "name" => "checkout-ci", "path" => "\\", "queueStatus" => "enabled", "latestCompletedBuild" => { "result" => "failed" },
                                     "repository" => { "type" => "TfsGit", "name" => "checkout", "defaultBranch" => "refs/heads/main" },
                                     "_links" => { "web" => { "href" => "https://dev.azure.com/fabrikam/Shop/_build/definition?definitionId=12" } } },
                                   { "id" => 13, "name" => "site", "path" => "\\web", "queueStatus" => "disabled",
                                     "repository" => { "type" => "GitHub", "name" => "acme/site", "url" => "https://github.com/acme/site.git" } } ], false ])
        AzureDevops::Infrastructure.any_instance.stubs(:files).returns([])

        snapshot = @pack.map_of(@row)

        repo, pipeline, github_pipeline, github = snapshot.resources.sort_by { |found| [ found.provider, found.kind == ResourceMap::KIND_PIPELINE ? 1 : 0, found.external_id ] }
                                                          .then { |found| [ found.find { |each| each.external_id == "Shop/checkout" }, found.find { |each| each.external_id == "Shop/12" },
                                                                            found.find { |each| each.external_id == "Shop/13" }, found.find { |each| each.provider == "github" } ] }
        assert_equal [ "fabrikam/Shop", ResourceMap::KIND_REPOSITORY, WEB, "main" ], [ repo.account, repo.kind, repo.url, repo.details["branch"] ]
        assert_equal [ "Shop/checkout-ci", "failed", "checkout" ], [ pipeline.name, pipeline.status, pipeline.details["repository"] ]
        assert_equal [ "Shop/web/site", "disabled" ], [ github_pipeline.name, github_pipeline.status ]
        assert_equal "acme/site", github.external_id
        assert_equal [ [ pipeline.key, repo.key ], [ github_pipeline.key, github.key ] ].sort,
                     snapshot.links.map { |link| [ link.from, link.to ] }.sort
        assert snapshot.links.all? { |link| link.relation == ResourceMap::RELATION_BUILT_FROM }
        assert_not snapshot.resources.any? { |found| found.external_id == "Shop/old" }, "a disabled repository is not on the map"
      end

      test "a change re-reads one repository or pipeline, gone only when Azure DevOps answers not found, and nothing outside the projects read" do
        AzureDevopsApi.any_instance.stubs(:get).with("/Shop/_apis/git/repositories/gone").raises(AzureDevopsApi::NotFound, "Azure DevOps answered 404")
        snapshot = @pack.map_refresh(@row, ResourceMap::Scope.new(kind: ResourceMap::KIND_REPOSITORY, external_id: "Shop/gone"))
        assert_equal [ [ "azure_devops", "fabrikam/Shop", ResourceMap::KIND_REPOSITORY, "Shop/gone" ] ], snapshot.gone

        AzureDevopsApi.any_instance.stubs(:get).with("/Shop/_apis/build/definitions/12", { "includeLatestBuilds" => true }).raises(AzureDevopsApi::NotFound, "404")
        assert_equal [ [ "azure_devops", "fabrikam/Shop", ResourceMap::KIND_PIPELINE, "Shop/12" ] ],
                     @pack.map_refresh(@row, ResourceMap::Scope.new(kind: ResourceMap::KIND_PIPELINE, external_id: "Shop/12")).gone

        assert_empty @pack.map_refresh(@row, ResourceMap::Scope.new(kind: ResourceMap::KIND_REPOSITORY, external_id: "Other/web")).resources
        assert_nil @pack.map_refresh(@row, ResourceMap::Scope.new(kind: ResourceMap::KIND_REPOSITORY))
      end

      test "the general read keeps to the projects the connection reads, refuses a run's log, and links the page it read" do
        AzureDevopsApi.any_instance.expects(:read).with("/Shop/_apis/policy/configurations", {}).returns("value" => [ { "id" => 1 } ])
        assert_match PROJECT_WEB, call(:api_read, "path" => "/Shop/_apis/policy/configurations")

        AzureDevopsApi.any_instance.expects(:read).with("/_apis/projects", {}).returns("value" => [])
        call(:api_read, "path" => "/_apis/projects")

        assert_match "reads Shop only", assert_raises(PolicyRefusal) { call(:api_read, "path" => "/Other/_apis/git/repositories") }.message
        assert_match "Read it with job_log", assert_raises(PolicyRefusal) { call(:api_read, "path" => "/Shop/_apis/build/builds/7/logs/3") }.message
      end

      test "the sandbox fetches from the organization's Azure Repos address with the token, and never follows a redirect" do
        remote = @pack.send(:code_remote, @row)

        assert_equal "https://dev.azure.com/fabrikam/Fabrikam%20Fiber/_git/web%20app", remote.url("Fabrikam Fiber/web app")
        assert_equal [ AzureDevops::GIT_USER, "pat-token", [ "http.followRedirects=false" ] ], [ remote.user, remote.token.call, remote.options ]
      end

      test "a pull request's address in this organization names its repository and number, and no other address does" do
        assert_equal [ "Shop/checkout", 42 ], @pack.pull_request_at(@row, "#{WEB}/pullrequest/42")
        assert_nil @pack.pull_request_at(@row, "https://dev.azure.com/other/Shop/_git/checkout/pullrequest/42")
        assert_nil @pack.pull_request_at(@row, "https://dev.azure.com/fabrikam/Other/_git/checkout/pullrequest/42")
        assert_nil @pack.pull_request_at(@row, "https://github.com/acme/web/pull/42")
      end

      test "a flag is a comment thread on the pull request" do
        AzureDevopsApi.any_instance.expects(:post).with("#{REPO}/pullRequests/42/threads",
                                                        { "comments" => [ { "parentCommentId" => 0, "content" => "Touches a flag.", "commentType" => 1 } ], "status" => 1 })
        assert_nil @pack.flag_pull_request(@row, repository: "Shop/checkout", number: 42, body: "Touches a flag.")
      end

      test "a pipeline on the map is asked through the pipeline, a repository through the repository" do
        pipeline = ResourceMap::Resource.new(kind: ResourceMap::KIND_PIPELINE, external_id: "Shop/12", name: "Shop/checkout-ci", details: {})
        route = Capabilities::AzureDevops.route(Capabilities::HISTORY, pipeline, { "run" => "7" }, tool: nil)
        assert_equal [ "ci_runs", { "pipeline" => "Shop/12", "run" => "7" } ], [ route.tool_name, route.arguments ]

        repo = ResourceMap::Resource.new(kind: ResourceMap::KIND_REPOSITORY, external_id: "Shop/checkout", name: "Shop/checkout", details: {})
        assert_equal({ "repo" => "Shop/checkout" }, Capabilities::AzureDevops.route(Capabilities::STATUS, repo, {}, tool: nil).arguments)
      end

      private

      # Each call on a pack of its own, as the executor makes one per call, so a project one call named is never another's.
      def call(tool, arguments)
        result = AzureDevops.new(@integration, box_key: "investigation-1").call(tool.to_s, environment_row: @row, arguments: arguments)
        result.is_a?(Hash) ? result["content"].map { |part| part["text"] }.join("\n") : result
      end

      def stub_get(path, query_or_body, body = nil)
        if body
          AzureDevopsApi.any_instance.stubs(:get).with(path, query_or_body).returns(body)
        else
          AzureDevopsApi.any_instance.stubs(:get).with(path).returns(query_or_body)
        end
      end

      def repository
        { "id" => "repo-guid", "name" => "checkout", "project" => { "name" => "Shop" }, "defaultBranch" => "refs/heads/main", "webUrl" => WEB, "size" => 10 }
      end

      def build(id, status, result, start: nil, finish: nil)
        { "id" => id, "buildNumber" => "20261001.#{id}", "status" => status, "result" => result, "definition" => { "id" => 12, "name" => "checkout-ci" },
          "repository" => { "id" => "repo-guid", "name" => "checkout" }, "sourceBranch" => "refs/heads/main", "sourceVersion" => SHA, "reason" => "individualCI",
          "queueTime" => start, "startTime" => start, "finishTime" => finish, "_links" => { "web" => { "href" => "https://dev.azure.com/fabrikam/Shop/_build/results?buildId=#{id}" } } }
      end

      def timeline_records
        [ { "id" => "stage", "type" => "Stage", "name" => "Build" },
          { "id" => "phase", "type" => "Phase", "name" => "Compile", "parentId" => "stage" },
          { "id" => "compile", "type" => "Job", "name" => "Compile", "parentId" => "phase", "state" => "completed", "result" => "succeeded",
            "startTime" => "2026-10-01T10:00:00Z", "finishTime" => "2026-10-01T10:02:00Z", "log" => { "id" => 3 } },
          { "id" => "test", "type" => "Job", "name" => "Test", "parentId" => "phase", "state" => "completed", "result" => "failed",
            "startTime" => "2026-10-01T10:02:00Z", "finishTime" => "2026-10-01T10:05:00Z", "log" => { "id" => 5 } },
          { "id" => "task", "type" => "Task", "name" => "Run tests", "parentId" => "test", "state" => "completed", "result" => "failed", "order" => 1,
            "finishTime" => "2026-10-01T10:04:30Z", "log" => { "id" => 6 }, "issues" => [ { "type" => "error", "message" => "Tests failed" } ] },
          { "id" => "lint", "type" => "Job", "name" => "Lint", "parentId" => "phase", "state" => "completed", "result" => "skipped" } ]
      end

      def stub_environments
        stub_get("/Shop/_apis/distributedtask/environments", { "$top" => 50 }, "value" => [ { "id" => 3, "name" => "production" } ])
        stub_get("/Shop/_apis/distributedtask/environments/3/environmentdeploymentrecords", { "top" => 30 },
                 "value" => [ { "id" => 41, "planType" => "Build", "result" => "succeeded", "owner" => { "id" => 7, "name" => "20261001.7" }, "definition" => { "id" => 12, "name" => "checkout-ci" },
                                "stageName" => "Deploy", "jobName" => "Release", "startTime" => "2026-10-01T10:00:00Z", "finishTime" => "2026-10-01T10:10:00Z" },
                              { "id" => 40, "planType" => "Build", "result" => "succeeded", "owner" => { "id" => 8, "name" => "20261001.8" }, "definition" => { "id" => 14, "name" => "web-ci" },
                                "startTime" => "2026-10-01T09:00:00Z", "finishTime" => "2026-10-01T09:10:00Z" } ])
        stub_get(BUILDS, { "buildIds" => "7,8" },
                 "value" => [ build(7, "completed", "succeeded").merge("requestedFor" => { "displayName" => "Ana" }),
                              build(8, "completed", "succeeded").merge("repository" => { "id" => "web-guid", "name" => "web" }) ])
      end
    end
  end
end

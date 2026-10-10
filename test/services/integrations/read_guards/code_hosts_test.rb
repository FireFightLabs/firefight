require "test_helper"

module Integrations
  module ReadGuards
    # The read guards of GitHub, GitLab and Bitbucket, each only ever a GET, so what they settle is which GETs answer
    # secrets or a download.
    class CodeHostsTest < ActiveSupport::TestCase
      test "each guards api_read only, and a plain GET reads" do
        { Github => "/repos/acme/web/environments", Gitlab => "/projects/12/environments", Bitbucket => "/repositories/acme/web/environments" }.each do |guard, path|
          assert guard.guards?(ApiReads::TOOL)
          assert_not guard.guards?("fetch_file")
          assert guard.reads?(ApiReads::TOOL, "path" => path, "query" => { "per_page" => 5 }), path
        end
      end

      test "GitHub's downloads are refused by Firefight's rule, its secrets are read as names, and its webhooks keep their host" do
        %w[/repos/acme/web/zipball/main /repos/acme/web/actions/runs/1/logs /repos/acme/web/actions/runs/1/attempts/2/logs
           /repos/acme/web/actions/jobs/9/logs /repos/acme/web/actions/artifacts/3/zip].each do |path|
          assert_raises(PolicyRefusal, path) { Github.reading(ApiReads::TOOL, "path" => path) }
        end
        %w[/repos/acme/web/actions/secrets /repos/acme/web/dependabot/secrets/X /repos/acme/web/environments/prod/secrets].each do |path|
          assert Github.secret?(path), path
        end
        assert_not Github.secret?("/repos/acme/web/actions/variables")
        assert Github.webhooks?("/repos/acme/web/hooks")
        assert_not Github.secret?("/repos/acme/web/hooks")
        assert Github.reads?(ApiReads::TOOL, "path" => "/repos/acme/web/actions/artifacts/3")
      end

      test "GitLab's Terraform state, raw files, job logs and downloads are refused, and its variables, triggers and integrations are read as names" do
        %w[/projects/12/terraform/state/prod /projects/12/jobs/9/trace /projects/12/jobs/9/artifacts /projects/12/repository/archive.zip
           /projects/12/repository/files/app.rb/raw /projects/12/secure_files/4/download /projects/12/packages/generic/app/1.0/app.tgz].each do |path|
          assert_raises(PolicyRefusal, path) { Gitlab.reading(ApiReads::TOOL, "path" => path) }
        end
        %w[/projects/12/variables /groups/3/variables/KEY /admin/ci/variables /projects/12/triggers /projects/12/integrations].each do |path|
          assert Gitlab.secret?(path), path
        end
        assert_not Gitlab.secret?("/projects/12/environments")
        assert Gitlab.webhooks?("/projects/12/hooks")
      end

      test "Bitbucket's downloads, sources, diffs and step logs are refused, its variables are read as names, and its webhooks keep their host" do
        %w[/repositories/acme/web/downloads/app.zip /repositories/acme/web/src/main/app.rb /repositories/acme/web/diff/a..b
           /repositories/acme/web/pipelines/p1/steps/s1/log].each do |path|
          assert_raises(PolicyRefusal, path) { Bitbucket.reading(ApiReads::TOOL, "path" => path) }
        end
        %w[/repositories/acme/web/pipelines_config/variables /workspaces/acme/pipelines-config/variables
           /repositories/acme/web/deployments_config/environments/e1/variables].each do |path|
          assert Bitbucket.secret?(path), path
        end
        assert Bitbucket.reads?(ApiReads::TOOL, "path" => "/repositories/acme/web/downloads")
        assert Bitbucket.webhooks?("/repositories/acme/web/hooks")
      end
    end
  end
end

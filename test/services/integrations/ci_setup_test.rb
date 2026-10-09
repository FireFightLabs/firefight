require "test_helper"

module Integrations
  # A repository's setup read from its own CI, through each code host's pack, and kept the first time it is asked for.
  class CiSetupTest < ActiveSupport::TestCase
    WORKFLOW = <<~YAML.freeze
      name: CI
      on: [push, pull_request]
      env:
        RAILS_ENV: test
        SLACK_TOKEN: ${{ secrets.SLACK_TOKEN }}
      jobs:
        lint:
          runs-on: ubuntu-latest
          steps:
            - uses: actions/checkout@v4
            - run: bin/rubocop
        test:
          runs-on: ubuntu-latest
          services:
            postgres:
              image: postgres:16-alpine
              env:
                POSTGRES_USER: app
                POSTGRES_PASSWORD: postgres
                POSTGRES_DB: app_test
              ports: ["5433:5432"]
              options: --health-cmd pg_isready
            redis:
              image: redis:7
              ports: ["6379"]
            search:
              image: ${{ matrix.search }}
          env:
            DATABASE_URL: postgres://app:postgres@localhost:5433/app_test
          steps:
            - uses: actions/checkout@v4
            - uses: ruby/setup-ruby@v1
              with:
                bundler-cache: true
            - name: Build assets
              working-directory: web
              run: |
                npm ci
                npm run build
            - run: bin/rails db:schema:load
              env:
                SECRET_KEY_BASE: dummy
            - run: echo "${{ github.sha }}" > REVISION
            - run: bin/rails test
            - run: bin/upload-coverage
    YAML

    setup do
      @workspace = workspaces(:slack_workspace_one)
    end

    test "GitHub's setup is the job with services: their images, ports and variables, the variables, and the run steps before the tests" do
      row = github_row
      stub_workflows("ci.yml" => WORKFLOW, "release.yaml" => "on: push\njobs:\n  ship:\n    steps:\n      - run: bin/ship\n", "README.md" => "x")

      found = CiSetup.read(row, "acme/api")

      assert_equal ".github/workflows/ci.yml, job test", found.source
      assert_equal [
        { "name" => "postgres", "image" => "postgres:16-alpine", "port" => 5433, "env" => { "POSTGRES_USER" => "app", "POSTGRES_PASSWORD" => "postgres", "POSTGRES_DB" => "app_test" } },
        { "name" => "redis", "image" => "redis:7", "env" => {} }
      ], found.services
      assert_equal({ "RAILS_ENV" => "test", "DATABASE_URL" => "postgres://app@localhost:5433/app_test", "SECRET_KEY_BASE" => "dummy" }, found.env)
      assert_equal [ "cd web\nnpm ci\nnpm run build", "bin/rails db:schema:load" ], found.commands
      assert_equal [
        "Left out the search service, whose image only GitHub fills in.",
        "Left out 2 steps using an action, such as actions/setup-node, since the sandbox installs what the lockfiles and version files ask for.",
        "Left out 1 step using GitHub expressions, which only GitHub fills in.",
        "Left out the command that runs the tests (bin/rails test), since Halon runs the tests it needs itself.",
        "Left out 1 step after the tests.",
        "Left out SLACK_TOKEN, which the CI system fills in itself.",
        "Took the password out of DATABASE_URL, since the sandbox's services take any password."
      ], found.notes
    end

    test "a job that runs in a container reaches its services by name, which here is the box itself" do
      row = github_row
      stub_workflows("ci.yml" => <<~YAML)
        jobs:
          test:
            container: node:20
            services:
              db:
                image: postgres:16
            env:
              DATABASE_URL: postgres://postgres@db:5432/postgres
              DB_HOST: db
              DB_NAME: db
            steps:
              - run: npm ci
              - run: npm test
      YAML

      found = CiSetup.read(row, "acme/api")

      assert_equal({ "DATABASE_URL" => "postgres://postgres@127.0.0.1:5432/postgres", "DB_HOST" => "127.0.0.1", "DB_NAME" => "db" }, found.env)
      assert_includes found.notes, "This job runs in a container and reaches its services by name, so here they are reached on 127.0.0.1."
    end

    test "a repository with no workflow that runs commands says so in GitHub's words" do
      row = github_row
      GithubApp.stubs(:get).with("/repos/acme/api/contents/.github/workflows", token: "ghs_token").raises(GithubApp::NotFound, "GitHub answered 404")

      error = assert_raises(CiSetup::Missing) { CiSetup.read(row, "acme/api") }

      assert_equal "acme/api has no .github/workflows folder.", error.message
    end

    test "GitLab's setup is the job with services, after what it extends, its scripts kept in one shell, its services reached on the box" do
      integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "gitlab", name: "GitLab")
      row = integration.integration_environments.create!
      Packs::Gitlab.store_credentials!(row, Packs::Gitlab::TOKEN => "glpat-token")
      GitlabApi.any_instance.stubs(:text).with("/projects/acme%2Fplatform%2Fapi/repository/files/.gitlab-ci.yml/raw", "ref" => "HEAD").returns(<<~YAML)
        variables:
          POSTGRES_DB: app_test
          POSTGRES_USER: runner
          DATABASE_URL: postgres://$POSTGRES_USER@postgres:5432/$POSTGRES_DB
          DEPLOY_KEY: $DEPLOY_KEY_FROM_SETTINGS
        .ruby:
          image: ruby:3.4
          before_script:
            - bundle install
        lint:
          script: [ bin/rubocop ]
        test:
          extends: .ruby
          services:
            - postgres:16
            - name: redis:7
              alias: cache
          script:
            - bin/rails db:schema:load
            - bin/rails test
      YAML

      found = CiSetup.read(row, "acme/platform/api")

      assert_equal ".gitlab-ci.yml, job test", found.source
      assert_equal [ "postgres", "redis" ], found.services.map { |service| service["name"] }
      assert_equal({ "POSTGRES_DB" => "app_test", "POSTGRES_USER" => "runner", "DATABASE_URL" => "postgres://runner@127.0.0.1:5432/app_test" }, found.env)
      assert_equal [ "set -e\nbundle install\nbin/rails db:schema:load" ], found.commands
      assert_includes found.notes, "Left out DEPLOY_KEY, which the CI system fills in itself."
      assert_includes found.notes, "GitLab reaches this job's services at postgres, cache, and redis, so here they are reached on 127.0.0.1."
    end

    test "Bitbucket's setup is the step with services, from the services its definitions name" do
      integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "bitbucket", name: "Bitbucket")
      row = integration.integration_environments.create!
      row.store_fields!(Packs::Bitbucket::WORKSPACE => "acme")
      Packs::Bitbucket.store_credentials!(row, Packs::Bitbucket::TOKEN => "bb-token")
      BitbucketApi.any_instance.stubs(:get).with("/repositories/acme/api").returns("mainbranch" => { "name" => "main" })
      BitbucketApi.any_instance.stubs(:get).with("/repositories/acme/api/commits/main", "pagelen" => 1).returns("values" => [ { "hash" => "c0ffee" } ])
      BitbucketApi.any_instance.stubs(:text).with("/repositories/acme/api/src/c0ffee/bitbucket-pipelines.yml").returns(<<~YAML)
        definitions:
          services:
            postgres:
              image: postgres:15
              variables:
                POSTGRES_DB: app_test
        pipelines:
          default:
            - step:
                name: Lint
                script: [ npm run lint ]
            - parallel:
                - step:
                    name: Tests
                    services: [ postgres, docker ]
                    script:
                      - npm ci
                      - pipe: atlassian/slack-notify:2.0.0
                      - npx prisma migrate deploy
                      - npm test
      YAML

      found = CiSetup.read(row, "acme/api")

      assert_equal "bitbucket-pipelines.yml, step Tests", found.source
      assert_equal [ { "name" => "postgres", "image" => "postgres:15", "env" => { "POSTGRES_DB" => "app_test" } } ], found.services
      assert_equal [ "set -e\nnpm ci\nnpx prisma migrate deploy" ], found.commands
      assert_includes found.notes, "Left out 1 step running a pipe, which only Bitbucket runs."
    end

    test "a repository's setup is read from CI the first time it is asked for and kept, and an admin's edit is never read over" do
      row = github_row
      stub_workflows("ci.yml" => WORKFLOW)

      first = CiSetup.for(row, "acme/api")
      first.change!(services: [], env: { "RAILS_ENV" => "test" }, commands: [ "bin/setup" ])
      GithubApp.expects(:get).never
      again = CiSetup.for(row, "acme/api")

      assert_equal first, again
      assert_equal [ "bin/setup" ], again.commands
    end

    test "a host that cannot be read leaves the repository without a setup rather than failing" do
      row = github_row
      GithubApp.stubs(:get).raises(GithubApp::Error, "GitHub answered 500")

      assert_nil CiSetup.for(row, "acme/api")
      refute RepositorySetup.exists?(repository: "acme/api")
    end

    test "every code host reads its repositories' CI" do
      IntegrationProvider.all.select(&:holds_code).each do |provider|
        assert Packs.const_get(provider.key.camelize).method_defined?(:ci_setup), "#{provider.key} holds code but reads no CI"
      end
    end

    private

    def github_row
      integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
      GithubApp.stubs(:installation_token).returns("ghs_token")
      integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
    end

    def stub_workflows(files)
      listing = files.keys.map { |name| { "type" => "file", "name" => name, "path" => ".github/workflows/#{name}" } }
      GithubApp.stubs(:get).with("/repos/acme/api/contents/.github/workflows", token: "ghs_token").returns(listing)
      files.each do |name, text|
        GithubApp.stubs(:get).with("/repos/acme/api/contents/.github/workflows/#{name}", token: "ghs_token").returns("content" => Base64.encode64(text))
      end
    end
  end
end

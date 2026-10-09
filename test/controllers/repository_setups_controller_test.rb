require "test_helper"

class RepositorySetupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
    @github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    @row = @github.integration_environments.create!(base_config: { "installation_id" => "12345" })
    @details = integrations_path(Integration::DETAILS_QUERY_PARAM => @github.id)
  end

  test "an admin reads a repository's setup from its CI, and the toast says where from and what the sandbox cannot start" do
    found = Integrations::CiSetup::Found.new(services: [ { "name" => "postgres", "image" => "postgres:16" }, { "name" => "mysql", "image" => "mysql:8" } ],
                                             env: { "RAILS_ENV" => "test" }, commands: [ "bin/rails db:prepare" ], source: ".github/workflows/ci.yml, job test")
    Integrations::CiSetup.expects(:read).with(@row, "acme/api").returns(found)

    post integration_repository_setups_url(@github), params: { repository: " acme/api ", read_from_ci: true }

    assert_redirected_to @details
    setup = @github.repository_setups.find_by!(repository: "acme/api")
    assert_equal [ "bin/rails db:prepare" ], setup.commands
    assert_equal "Read acme/api's setup from .github/workflows/ci.yml, job test. The sandbox cannot start mysql, so Halon prepares acme/api without it.", flash[:notice]
  end

  test "a repository whose CI cannot be read stays on the form with why, and nothing is kept" do
    Integrations::CiSetup.expects(:read).raises(Integrations::CiSetup::Missing, "acme/api has no .github/workflows folder.")

    post integration_repository_setups_url(@github), params: { repository: "acme/api", read_from_ci: true }

    assert_redirected_to @details
    assert_equal({ "repository" => "acme/api has no .github/workflows folder." }, session[:inertia_errors].stringify_keys)
    refute @github.repository_setups.exists?

    post integration_repository_setups_url(@github), params: { repository: "acme/api", services: [ { name: "postgres" } ], commands: [ "bin/setup" ] }

    assert_equal "Saved how acme/api is set up before its tests.", flash[:notice]
    assert_equal [ "bin/setup" ], @github.repository_setups.find_by!(repository: "acme/api").commands, "a repository with no CI is set up by hand"
  end

  test "an admin sets a repository up by hand, changes it and clears it, each with a toast" do
    post integration_repository_setups_url(@github), params: {
      repository: "acme/web", services: [ { name: "redis", image: "redis:7", port: "6380", env: [ { name: "REDIS_ARGS", value: "--save ''" } ] } ],
      env: [ { name: "NODE_ENV", value: "test" } ], commands: [ "npm run build" ]
    }

    setup = @github.repository_setups.find_by!(repository: "acme/web")
    assert_equal "Saved how acme/web is set up before its tests.", flash[:notice]
    assert_equal [ { "name" => "redis", "image" => "redis:7", "port" => 6380, "env" => { "REDIS_ARGS" => "--save ''" } } ], setup.services
    assert setup.edited_at

    patch integration_repository_setup_url(@github, setup), params: { services: [], env: [ { name: "PATH", value: "/x" } ], commands: [] }

    assert_equal({ "setup" => "The sandbox sets PATH itself, so a setup cannot." }, session[:inertia_errors].stringify_keys)
    assert_equal({ "NODE_ENV" => "test" }, setup.reload.env)

    patch integration_repository_setup_url(@github, setup), params: { env: [ { name: "NODE_ENV", value: "ci" } ], commands: [ "npm ci" ] }

    assert_equal "Saved how acme/web is set up before its tests.", flash[:notice]
    assert_equal [ [], { "NODE_ENV" => "ci" }, [ "npm ci" ] ], [ setup.reload.services, setup.env, setup.commands ]

    delete integration_repository_setup_url(@github, setup)

    assert_redirected_to @details
    assert_equal "Cleared acme/web's setup. Halon reads it from CI again the next time it prepares acme/web.", flash[:notice]
    refute RepositorySetup.exists?(setup.id)
  end

  test "reading again replaces an admin's changes, and a failure to read says so in a toast and keeps what was there" do
    setup = @github.repository_setups.create!(workspace: @workspace, repository: "acme/api")
    setup.change!(services: [], env: {}, commands: [ "bin/setup" ])
    Integrations::CiSetup.stubs(:read).raises(Integrations::Error, "GitHub answered 500").then
                         .returns(Integrations::CiSetup::Found.new(services: [], env: {}, commands: [ "bin/rails db:prepare" ], source: ".github/workflows/ci.yml, job test"))

    post derive_integration_repository_setup_url(@github, setup)

    assert_equal "Could not reach the code host to read acme/api's CI. Try again in a moment.", flash[:alert]
    assert_equal [ "bin/setup" ], setup.reload.commands

    post derive_integration_repository_setup_url(@github, setup)

    assert_equal "Read acme/api's setup from .github/workflows/ci.yml, job test.", flash[:notice]
    assert_equal [ [ "bin/rails db:prepare" ], nil ], [ setup.reload.commands, setup.edited_at ]
  end

  test "a repository already set up, or a connection that holds no code, is refused, and only an admin changes a setup" do
    @github.repository_setups.create!(workspace: @workspace, repository: "acme/api")
    sentry = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "sentry", name: "Sentry", settings: { "server_url" => "https://mcp.sentry.example/mcp" })

    post integration_repository_setups_url(@github), params: { repository: "acme/api", read_from_ci: true }
    assert_equal({ "repository" => "acme/api already has a setup here. Edit it, or read it from CI again." }, session[:inertia_errors].stringify_keys)

    post integration_repository_setups_url(sentry), params: { repository: "acme/api" }
    assert_equal({ "repository" => "Sentry holds no code, so it has no repositories to set up." }, session[:inertia_errors].stringify_keys)

    sign_in(users(:bob), @workspace)
    post integration_repository_setups_url(@github), params: { repository: "acme/web", commands: [ "x" ] }
    refute @github.repository_setups.exists?(repository: "acme/web")
  end

  test "the connection's details list each repository's setup, with what the sandbox cannot start" do
    setup = @github.repository_setups.create!(workspace: @workspace, repository: "acme/api")
    setup.derived!(services: [ { "name" => "mysql", "image" => "mysql:8", "port" => 3306 } ], env: { "RAILS_ENV" => "test" }, commands: [ "bin/setup" ],
                   source: ".github/workflows/ci.yml, job test", notes: [ "Left out 1 step after the tests." ])

    get integrations_url, headers: inertia_headers

    shown = inertia_props["integrations"].find { |integration| integration["name"] == "GitHub" }["setups"].sole
    assert_equal [ "acme/api", [ "mysql" ], [ "Left out 1 step after the tests." ], ".github/workflows/ci.yml, job test" ],
                 shown.values_at("repository", "unstartableServices", "notes", "derivedFrom")
    assert_equal [ { "name" => "mysql", "image" => "mysql:8", "port" => 3306, "env" => {} } ], shown["services"]
  end
end

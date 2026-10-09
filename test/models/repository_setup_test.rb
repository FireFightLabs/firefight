require "test_helper"

class RepositorySetupTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    @setup = @github.repository_setups.new(workspace: @workspace, repository: "acme/api")
  end

  test "what an admin gives is kept trimmed, a command keeping its lines, variables arriving as pairs" do
    refusal = @setup.change!(services: [ { "name" => " Postgres ", "image" => "postgres:16", "port" => "5433", "env" => [ { "name" => "POSTGRES_DB", "value" => "app_test" } ] } ],
                             env: [ { "name" => "RAILS_ENV", "value" => "test" }, { "name" => " ", "value" => "dropped" } ],
                             commands: [ "cd web\r\nnpm run build", "  ", "bin/rails db:prepare" ])

    assert_nil refusal
    @setup.reload
    assert_equal [ { "name" => "postgres", "image" => "postgres:16", "port" => 5433, "env" => { "POSTGRES_DB" => "app_test" } } ], @setup.services
    assert_equal({ "RAILS_ENV" => "test" }, @setup.env)
    assert_equal [ "cd web\nnpm run build", "bin/rails db:prepare" ], @setup.commands
    assert @setup.edited_at
    assert_equal({ "services" => [ { "name" => "postgres", "port" => 5433, "env" => { "POSTGRES_DB" => "app_test" } } ],
                   "env" => { "RAILS_ENV" => "test" }, "commands" => [ "cd web\nnpm run build", "bin/rails db:prepare" ] }, @setup.for_box)
  end

  test "a setup the sandbox could not use, or that would hold a credential, is refused with why and nothing is saved" do
    refusals = {
      [ [], [ { "name" => "A", "value" => "1" }, { "name" => "A", "value" => "2" } ], [] ] => "A is set twice. Keep one.",
      [ [], { "PATH" => "/opt/bin" }, [] ] => "The sandbox sets PATH itself, so a setup cannot.",
      [ [], { "MISE_YES" => "0" }, [] ] => "The sandbox sets MISE_YES itself, so a setup cannot.",
      [ [], { "2FAST" => "x" }, [] ] => "2FAST is not a variable name. Use letters, digits and underscores, starting with a letter.",
      [ [], { "DATABASE_URL" => "postgres://app:hunter2@127.0.0.1/app" }, [] ] =>
        "DATABASE_URL holds a password. The sandbox's services take any password, so take it out, as in postgres://postgres@127.0.0.1:5432/app_test.",
      [ [], { "TOKEN" => "ghp_#{'a' * 36}" }, [] ] =>
        "TOKEN looks like it holds a credential, and Firefight keeps credentials only in a connection's settings, so it is not saved.",
      [ [ { "name" => "postgres", "port" => "80" } ], {}, [] ] => "postgres's port must be a number from 1024 to 65535.",
      [ [ { "name" => "My DB" } ], {}, [] ] => "my db is not a service name. Use lower case letters, digits, dots and dashes, such as postgres.",
      [ [], {}, [ "x" * (RepositorySetup::COMMAND_LIMIT + 1) ] ] => "A command is longer than #{RepositorySetup::COMMAND_LIMIT} characters."
    }

    refusals.each do |(services, env, commands), said|
      assert_equal said, @setup.change!(services: services, env: env, commands: commands)
    end
    assert @setup.new_record?
  end

  test "reading from CI replaces what an admin changed, notes included, and the setup's digest follows what the sandbox is handed" do
    @setup.change!(services: [], env: { "RAILS_ENV" => "test" }, commands: [ "bin/setup" ])
    before = @setup.digest

    @setup.derived!(services: [ { "name" => "postgres", "image" => "postgres:16" }, { "name" => "mysql", "image" => "mysql:8" } ], env: { "RAILS_ENV" => "test" },
                    commands: [ "bin/setup" ], source: ".github/workflows/ci.yml, job test", notes: [ "Left out 2 steps after the tests." ])

    assert_nil @setup.edited_at
    assert_equal ".github/workflows/ci.yml, job test", @setup.derived_from
    assert_equal [ "Left out 2 steps after the tests." ], @setup.notes
    assert_equal [ "mysql" ], @setup.unstartable_services
    refute_equal before, @setup.digest
    assert_equal @setup.digest, RepositorySetup.find(@setup.id).digest
  end

  test "a connection keeps one setup per repository, and an admin adds one only to a code host, named as one" do
    @setup.change!(services: [], env: {}, commands: [])
    sentry = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "sentry", name: "Sentry", settings: { "server_url" => "https://mcp.sentry.example/mcp" })

    assert_equal "acme/api already has a setup here. Edit it, or read it from CI again.", @github.repository_setup_blocked_reason("acme/api")
    assert_equal "Name the repository, such as acme/api.", @github.repository_setup_blocked_reason(" ")
    assert_equal "api is not a repository name. Write it as owner/name, such as acme/api.", @github.repository_setup_blocked_reason("api")
    assert_nil @github.repository_setup_blocked_reason("acme/platform/web")
    assert_equal "Sentry holds no code, so it has no repositories to set up.", sentry.repository_setup_blocked_reason("acme/web")
    assert_equal "GitHub has no environment switched on, so its CI cannot be read.", @github.ci_read_blocked_reason
  end
end

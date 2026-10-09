require "application_system_test_case"

class RepositorySetupTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
    @integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    @integration.integration_environments.create!(health_status: IntegrationEnvironment::HEALTH_HEALTHY)
    @integration.tools.create!(name: "fix_code", read_only: false, enabled: true, description: "Write a code change and open it as a pull request")
    Integrations::CiSetup.stubs(:read).returns(Integrations::CiSetup::Found.new(
      services: [ { "name" => "postgres", "image" => "postgres:16", "port" => 5432, "env" => { "POSTGRES_DB" => "app_test" } },
                  { "name" => "elasticsearch", "image" => "elasticsearch:8.15.0" } ],
      env: { "RAILS_ENV" => "test", "DATABASE_URL" => "postgres://postgres@127.0.0.1:5432/app_test" },
      commands: [ "bin/rails db:schema:load", "cd web\nnpm ci\nnpm run build" ], source: ".github/workflows/ci.yml, job test",
      notes: [ "Left out 2 steps using an action, such as actions/setup-node, since the sandbox installs what the lockfiles and version files ask for.",
               "Left out the command that runs the tests (bin/rails test), since Halon runs the tests it needs itself." ]
    ))
  end

  test "an admin reads a repository's setup from CI, edits it and clears it, each with a toast" do
    visit integrations_path(Integration::DETAILS_QUERY_PARAM => @integration.id)

    assert_text "Repository setup"
    assert_text "No repository is set up yet. Halon reads each one from its CI when it first prepares it."
    find("p", text: "Repository setup").scroll_to(:center)
    page.save_screenshot(Rails.root.join("tmp/screenshots/repository-setup-empty.png"))

    click_on "Set up a repository"
    fill_in "Repository", with: "acme/api"
    click_on "Read from CI"

    assert_text "Read acme/api's setup from .github/workflows/ci.yml, job test. The sandbox cannot start elasticsearch, so Halon prepares acme/api without it."
    assert_text "postgres (postgres:16) on port 5432, elasticsearch (elasticsearch:8.15.0)"
    assert_text "RAILS_ENV=test"
    assert_text "Left out the command that runs the tests (bin/rails test)"
    find("p", text: "Repository setup").scroll_to(:top)
    page.save_screenshot(Rails.root.join("tmp/screenshots/repository-setup-derived.png"))

    click_on "Actions for acme/api"
    find("[role=menuitem]", text: "Edit").click
    assert_text "Edit acme/api's setup"
    fill_in "Variables", with: "RAILS_ENV=test\nPATH=/opt/bin"
    click_on "Save"
    assert_text "The sandbox sets PATH itself, so a setup cannot."
    fill_in "Variables", with: "RAILS_ENV=test\nDATABASE_URL=postgres://postgres@127.0.0.1:5432/app_test\nCI=true"
    page.save_screenshot(Rails.root.join("tmp/screenshots/repository-setup-editing.png"))
    click_on "Save"

    assert_text "Saved how acme/api is set up before its tests."
    assert_text "CI=true"
    assert_text "Changed here"
    setup = @integration.repository_setups.find_by!(repository: "acme/api")
    assert_equal "true", setup.env["CI"]

    click_on "Actions for acme/api"
    find("[role=menuitem]", text: "Clear").click
    assert_text "Clear acme/api's setup?"
    click_on "Clear"

    assert_text "Cleared acme/api's setup. Halon reads it from CI again the next time it prepares acme/api."
    assert_text "No repository is set up yet."
    refute RepositorySetup.exists?(setup.id)
  end
end

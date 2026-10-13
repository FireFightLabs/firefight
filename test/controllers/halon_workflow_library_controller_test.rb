require "test_helper"

class HalonWorkflowLibraryControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    sign_in(users(:alice), @workspace)
  end

  def item(version: 1, minutes: 5)
    Workflow::Library::Item.new(
      key: "cool_down", name: "Cool down", description: "Waits a while.", aliases: [], version: version,
      definition: { "trigger" => { "kind" => Workflow::Trigger::KIND_MANUAL, "inputs" => [] },
                    "steps" => [ { "id" => "step_wait", "name" => "wait", "kind" => DefinedWorkflow::KIND_DELAY, "config" => { "minutes" => minutes } } ],
                    "edges" => [], "outputs" => {} }
    )
  end

  def offer(*items) = Workflow::Library.stubs(:all).returns(items)

  test "the page lists Firefight's library with what each needs and the workspace's workflows with where they came from" do
    get halon_workflow_library_path, headers: inertia_headers

    disk = inertia_props["items"].find { |each| each["key"] == "disk_space_check" }
    assert_equal [ "Disk space check", Workflow::Trigger::KIND_SCHEDULE ], disk.values_at("name", "triggerKind")
    assert_nil disk["useBlockedReason"]
    assert_equal [], inertia_props["workflows"]
  end

  test "an item is used as it is or copied under a name, each saying so" do
    offer(item)

    post adopt_halon_library_workflow_path("cool_down")
    assert_equal "Cool down was made from Firefight's library and moves with its new versions. Publish its draft to run it.", flash[:notice]

    post adopt_halon_library_workflow_path("cool_down"), params: { name: "My cool down", following: false }
    assert_equal "My cool down was copied from Firefight's library as your own. Change its draft and publish it to run it.", flash[:notice]

    post adopt_halon_library_workflow_path("cool_down")
    assert_equal [ "Cool down already exists here, so give this one another name." ], session["inertia_errors"][:name]

    get halon_workflow_library_path, headers: inertia_headers
    assert_equal [ [ "Cool down", true ], [ "My cool down", false ] ], inertia_props["workflows"].map { |row| row.values_at("name", "following") }
    assert_equal [ "Cool down", "My cool down" ], inertia_props["items"].sole["usedBy"]
  end

  test "a copy sees what changed in a newer version, and takes it into a draft or keeps its own" do
    offer(item)
    copy = Workflow.from_library!(item, workspace: @workspace, by: @alice, following: false)
    copy.draft.publish!(by: @alice)
    offer(item(version: 2, minutes: 10))

    get halon_workflow_library_path, headers: inertia_headers
    update = inertia_props["workflows"].sole["libraryUpdate"]
    assert_equal [ 2, [ "Changed its settings of the step wait." ] ], [ update["version"], update["changes"].map { |change| change["text"] } ]

    post keep_own_halon_workflow_path(copy)
    assert_equal "Cool down keeps your steps. You are told again when Firefight ships a newer version.", flash[:notice]

    copy.reload.update!(library_dismissed_version: nil)
    post take_library_halon_workflow_path(copy)
    assert_equal "Cool down has a new draft, version 2, holding Firefight's version 2. Publish it to run it.", flash[:notice]

    post take_library_halon_workflow_path(copy)
    assert_equal "There is no newer version of Cool down in Firefight's library to take.", flash[:alert]
  end

  test "a workflow exports as a file and the file imports as a new draft" do
    offer(item)
    workflow = Workflow.from_library!(item, workspace: @workspace, by: @alice)

    get export_halon_workflow_path(workflow)
    assert_equal "application/json", response.media_type
    assert_match "cool_down.workflow.json", response.headers["Content-Disposition"]

    file = Rack::Test::UploadedFile.new(StringIO.new(response.body), "application/json", original_filename: "cool_down.workflow.json")
    post import_halon_workflow_path, params: { file: file, name: "Imported cool down" }
    assert_equal "Imported cool down was imported as a draft. Publish it to run it.", flash[:notice]

    post import_halon_workflow_path, params: { file: Rack::Test::UploadedFile.new(StringIO.new("nope"), "application/json", original_filename: "x.json") }
    assert_equal [ "The file is not readable JSON." ], session["inertia_errors"][:file]
  end

  test "without the workflows flag the page does not exist" do
    FeatureFlags.disable!(@workspace, FeatureFlags::WORKFLOWS)

    get halon_workflow_library_path

    assert_response :not_found
  end
end

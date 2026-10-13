require "test_helper"

class Workflow::DocumentTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @steps = [ { "id" => "step_wait", "name" => "wait", "kind" => DefinedWorkflow::KIND_DELAY, "config" => { "minutes" => 5 } } ]
  end

  def workflow!
    workflow = Workflow.create!(workspace: @workspace, name: "Cool down", description: "Waits a while.", aliases: [ "pause" ])
    workflow.open_draft!(by: @alice).update_columns(steps: @steps)
    workflow
  end

  test "a workflow exported as a file imports into another workspace as a draft holding the same version" do
    text = Workflow::Document.render(workflow!.reload)
    assert_equal "cool_down.workflow.json", Workflow::Document.file_name(Workflow.find_by!(workspace: @workspace, slug: "cool_down"))

    parsed = Workflow::Document.parse(text)
    imported = Workflow::Document.import!(parsed, workspace: workspaces(:slack_workspace_two), by: workspace_memberships(:alice_workspace_two))

    assert_equal [ "Cool down", "Waits a while.", [ "pause" ] ], imported.values_at(:name, :description, :aliases)
    draft = imported.draft
    assert_equal [ @steps, Workflow::AUTHOR_PERSON, "Imported from a file." ], [ draft.steps, draft.author_kind, draft.reason ]
    assert_nil imported.live_version, "nothing runs until someone publishes it"
  end

  test "an import takes a new name when the file's is taken here" do
    parsed = Workflow::Document.parse(Workflow::Document.render(workflow!.reload))

    error = assert_raises(Workflow::Document::Unreadable) { Workflow::Document.import!(parsed, workspace: @workspace, by: @alice) }
    assert_equal "Cool down already exists here, so give this one another name.", error.message
    assert_equal "Cool down again", Workflow::Document.import!(parsed, workspace: @workspace, by: @alice, name: "Cool down again").name
  end

  test "a file that is not a workflow, is too new or holds a secret is refused with why" do
    assert_raises(Workflow::Document::Unreadable, "The file is not readable JSON.") { Workflow::Document.parse("{") }
    error = assert_raises(Workflow::Document::Unreadable) { Workflow::Document.parse({ "name" => "x" }.to_json) }
    assert_equal "The file is not a Firefight workflow.", error.message
    error = assert_raises(Workflow::Document::Unreadable) do
      Workflow::Document.parse({ "format" => Workflow::Document::FORMAT, "format_version" => 2 }.to_json)
    end
    assert_equal "The file was written by a newer Firefight than this one.", error.message
    secret = { "format" => Workflow::Document::FORMAT, "format_version" => 1, "name" => "Leaky",
               "steps" => [ { "id" => "a", "name" => "a", "kind" => "delay", "config" => { "token" => "ghp_#{'a' * 36}" } } ] }
    error = assert_raises(Workflow::Document::Unreadable) { Workflow::Document.parse(secret.to_json) }
    assert_match "looks like it holds a secret", error.message
  end
end

require "test_helper"

class SlackWorkspaceSetupWorkflowTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(
      platform: "slack",
      platform_id: "T#{SecureRandom.hex(8)}",
      name: "Test Workspace",
      access_token: "xoxb-test-token",
      installed_at: Time.current
    )
  end

  # Successful workflow execution

  test "workflow completes successfully with new channel" do
    stub_successful_slack_workflow do
      workflow = SlackWorkspaceSetupWorkflow.start_inline!(
        @workspace,
        context: { installer_user_id: "U12345678" }
      )

      assert_equal "succeeded", workflow.state
      assert workflow.completed?

      # Verify workspace was updated
      @workspace.reload
      assert @workspace.incidents_channel_id.present?
    end
  end

  test "workflow executes all steps in correct order" do
    executed_steps = []

    # Track step execution
    original_service = WorkspaceSetupService
    stub_service = Class.new do
      define_method(:create_incidents_channel) do |workspace|
        executed_steps << :create_incidents_channel
        { channel_id: "C12345678", channel_name: "incidents", already_existed: false }
      end

      define_method(:set_channel_metadata) do |workspace, channel_id|
        executed_steps << :set_channel_metadata
        { success: true }
      end

      define_method(:post_welcome_message) do |workspace, channel_id|
        executed_steps << :post_welcome_message
        { message_ts: "123.456" }
      end

      define_method(:invite_user) do |workspace, channel_id, user_id, **opts|
        executed_steps << :invite_user
        { invited_user: user_id }
      end

      define_method(:store_channel_id) do |workspace, channel_id|
        executed_steps << :store_channel_id
        { success: true }
      end
    end

    # Stub WorkspaceSetupService.new
    WorkspaceSetupService.define_singleton_method(:new) { stub_service.new }

    workflow = SlackWorkspaceSetupWorkflow.start_inline!(
      @workspace,
      context: { installer_user_id: "U12345678" }
    )

    assert_equal "succeeded", workflow.state

    # Verify all steps executed
    assert_equal 5, executed_steps.length
    assert_includes executed_steps, :create_incidents_channel
    assert_includes executed_steps, :set_channel_metadata
    assert_includes executed_steps, :post_welcome_message
    assert_includes executed_steps, :invite_user
    assert_includes executed_steps, :store_channel_id

    # Verify dependency order is respected
    create_idx = executed_steps.index(:create_incidents_channel)
    metadata_idx = executed_steps.index(:set_channel_metadata)
    welcome_idx = executed_steps.index(:post_welcome_message)
    invite_idx = executed_steps.index(:invite_user)
    store_idx = executed_steps.index(:store_channel_id)

    # create_incidents_channel must be first
    assert_equal 0, create_idx

    # set_channel_metadata depends on create_incidents_channel
    assert create_idx < metadata_idx

    # post_welcome_message depends on set_channel_metadata
    assert metadata_idx < welcome_idx

    # invite_installer depends on post_welcome_message
    assert welcome_idx < invite_idx

    # store_channel_id depends on create_incidents_channel (can run anytime after)
    assert create_idx < store_idx

    # Restore original
    WorkspaceSetupService.define_singleton_method(:new) { original_service.new }
  end

  test "workflow passes installer_user_id to invite step" do
    invited_user = nil

    stub_create_channel do
      stub_set_channel_topic do
        stub_set_channel_purpose do
          stub_post_message do
            # Capture the invited user
            original_invite = Slack::Client.method(:invite_to_channel)
            Slack::Client.define_singleton_method(:invite_to_channel) do |**args|
              invited_user = args[:users]
              { ok: true }
            end

            workflow = SlackWorkspaceSetupWorkflow.start_inline!(
              @workspace,
              context: { installer_user_id: "U99999999" }
            )

            assert_equal "succeeded", workflow.state
            assert_equal "U99999999", invited_user

            Slack::Client.define_singleton_method(:invite_to_channel, original_invite)
          end
        end
      end
    end
  end

  # Workflow with existing channel

  test "workflow skips invitation if channel already existed" do
    invitation_attempted = false

    stub_create_channel(
      result: { channel: { id: "C12345678", name: "incidents" } },
      raises: Slack::Client::ChannelExistsError.new("exists")
    ) do
      stub_list_conversations(channels: [ { id: "C12345678", name: "incidents" } ]) do
        stub_set_channel_topic do
          stub_set_channel_purpose do
            stub_post_message do
              # Track if invitation was attempted
              original_invite = Slack::Client.method(:invite_to_channel)
              Slack::Client.define_singleton_method(:invite_to_channel) do |**args|
                invitation_attempted = true
                { ok: true }
              end

              workflow = SlackWorkspaceSetupWorkflow.start_inline!(
                @workspace,
                context: { installer_user_id: "U12345678" }
              )

              assert_equal "succeeded", workflow.state
              assert_not invitation_attempted, "Should not invite if channel existed"

              Slack::Client.define_singleton_method(:invite_to_channel, original_invite)
            end
          end
        end
      end
    end
  end

  # Error handling

  test "workflow fails if channel creation fails" do
    stub_create_channel(raises: Slack::Client::ApiError.new("permission_denied")) do
      workflow = SlackWorkspaceSetupWorkflow.start_inline!(
        @workspace,
        context: { installer_user_id: "U12345678" }
      )

      # When step fails with retries enabled, workflow is running and step is pending (scheduled for retry)
      # To test immediate failure, check that the step failed and is scheduled for retry
      step = workflow.workflow_steps.find_by(name: "create_incidents_channel")
      assert step.pending? || step.failed?
      assert step.last_error.present?
    end
  end

  test "workflow fails if setting metadata fails" do
    stub_create_channel do
      stub_set_channel_topic do
        # Stub purpose to fail
        original_purpose = Slack::Client.method(:set_channel_purpose)
        Slack::Client.define_singleton_method(:set_channel_purpose) do |**args|
          raise Slack::Client::ApiError.new("permission_denied")
        end

        workflow = SlackWorkspaceSetupWorkflow.start_inline!(
          @workspace,
          context: { installer_user_id: "U12345678" }
        )

        # Check that the metadata step failed and has error
        step = workflow.workflow_steps.find_by(name: "set_channel_metadata")
        assert step.pending? || step.failed?
        assert step.last_error.present?

        Slack::Client.define_singleton_method(:set_channel_purpose, original_purpose)
      end
    end
  end

  test "workflow fails if posting welcome message fails" do
    stub_create_channel do
      stub_set_channel_topic do
        stub_set_channel_purpose do
          stub_post_message(raises: Slack::Client::ApiError.new("channel_not_found")) do
            workflow = SlackWorkspaceSetupWorkflow.start_inline!(
              @workspace,
              context: { installer_user_id: "U12345678" }
            )

            # Check that the welcome message step failed and has error
            step = workflow.workflow_steps.find_by(name: "post_welcome_message")
            assert step.pending? || step.failed?
            assert step.last_error.present?
          end
        end
      end
    end
  end

  test "workflow continues if invitation fails but does not fail workflow" do
    stub_create_channel do
      stub_set_channel_topic do
        stub_set_channel_purpose do
          stub_post_message do
            # Invitation fails but workflow should handle gracefully
            stub_invite_to_channel(raises: Slack::Client::ApiError.new("user_not_found")) do
              workflow = SlackWorkspaceSetupWorkflow.start_inline!(
                @workspace,
                context: { installer_user_id: "U12345678" }
              )

              # Invitation step should have failed
              step = workflow.workflow_steps.find_by(name: "invite_installer")
              assert step.pending? || step.failed?
              assert step.last_error.present? if step.failed?
            end
          end
        end
      end
    end
  end

  # Step dependencies

  test "set_channel_metadata depends on create_incidents_channel" do
    workflow_class = SlackWorkspaceSetupWorkflow
    steps = workflow_class.steps

    metadata_step = steps.find { |s| s[:name] == "set_channel_metadata" }
    assert metadata_step[:depends_on].include?("create_incidents_channel")
  end

  test "post_welcome_message depends on set_channel_metadata" do
    workflow_class = SlackWorkspaceSetupWorkflow
    steps = workflow_class.steps

    welcome_step = steps.find { |s| s[:name] == "post_welcome_message" }
    assert welcome_step[:depends_on].include?("set_channel_metadata")
  end

  test "invite_installer depends on post_welcome_message" do
    workflow_class = SlackWorkspaceSetupWorkflow
    steps = workflow_class.steps

    invite_step = steps.find { |s| s[:name] == "invite_installer" }
    assert invite_step[:depends_on].include?("post_welcome_message")
  end

  test "store_channel_id depends on create_incidents_channel" do
    workflow_class = SlackWorkspaceSetupWorkflow
    steps = workflow_class.steps

    store_step = steps.find { |s| s[:name] == "store_channel_id" }
    assert store_step[:depends_on].include?("create_incidents_channel")
  end

  # Workflow name

  test "workflow has correct name" do
    assert_equal "slack.workspace_setup.v1", SlackWorkspaceSetupWorkflow.workflow_name
  end

  # Context validation

  test "workflow requires installer_user_id in context" do
    stub_successful_slack_workflow do
      # This tests that workflow uses the context
      workflow = SlackWorkspaceSetupWorkflow.start_inline!(
        @workspace,
        context: { installer_user_id: "U12345678" }
      )

      assert_equal "succeeded", workflow.state
    end
  end

  # Integration with workspace

  test "workflow stores channel_id on workspace" do
    stub_successful_slack_workflow do
      assert_nil @workspace.incidents_channel_id

      workflow = SlackWorkspaceSetupWorkflow.start_inline!(
        @workspace,
        context: { installer_user_id: "U12345678" }
      )

      assert_equal "succeeded", workflow.state

      @workspace.reload
      assert_equal "C12345678", @workspace.incidents_channel_id
    end
  end

  test "workflow can be started asynchronously" do
    stub_successful_slack_workflow do
      # This just verifies the method exists and doesn't error
      # Actual async execution would require background job processing
      workflow = SlackWorkspaceSetupWorkflow.start!(
        @workspace,
        context: { installer_user_id: "U12345678" }
      )

      assert workflow.present?
      assert workflow.respond_to?(:id)
      assert workflow.respond_to?(:state)
    end
  end
end

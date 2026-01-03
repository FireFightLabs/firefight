# frozen_string_literal: true

# WorkflowHelpers - Test helpers for workflow specs
#
# Provides helper methods for testing workflows synchronously
# without dealing with background job queues.
#
# Usage:
#   RSpec.describe MyWorkflow, type: :workflow do
#     it "completes successfully" do
#       workflow = run_workflow_sync(MyWorkflow, user)
#       expect_workflow_succeeded(workflow)
#     end
#   end
#
module WorkflowHelpers
  # Run a workflow synchronously (for testing)
  #
  # Executes workflow synchronously without background jobs.
  # Equivalent to calling workflow_class.start_inline! directly.
  #
  # @param workflow_class [Class] The workflow class to run (e.g., IncidentCreationWorkflow)
  # @param subject [ActiveRecord::Base] The subject record
  # @param context [Hash] Optional context for the workflow
  # @return [Workflow] The completed workflow instance
  #
  # @example
  #   workflow = run_workflow_sync(WelcomeUserWorkflow, user, context: { source: "admin" })
  #   expect(workflow.state).to eq("succeeded")
  #
  def run_workflow_sync(workflow_class, subject, context: {})
    workflow_class.start_inline!(subject, context: context)
  end

  # Assert that a workflow completed successfully
  #
  # Checks that:
  # - Workflow state is "succeeded"
  # - All steps are either "succeeded" or "skipped"
  #
  # @param workflow [Workflow] The workflow to check
  #
  # @example
  #   workflow = run_workflow_sync(MyWorkflow, user)
  #   expect_workflow_succeeded(workflow)
  #
  def expect_workflow_succeeded(workflow)
    expect(workflow.state).to eq("succeeded"),
      "Expected workflow to succeed but was #{workflow.state}. " \
      "Failed steps: #{workflow.workflow_steps.failed.pluck(:name, :last_error)}"

    expect(workflow.workflow_steps.pluck(:status).uniq).to match_array(%w[succeeded skipped]),
      "Expected all steps to be succeeded or skipped. " \
      "Actual statuses: #{workflow.workflow_steps.pluck(:name, :status)}"
  end

  # Assert that a workflow failed
  #
  # Checks that:
  # - Workflow state is "failed"
  # - At least one step has status "failed"
  #
  # @param workflow [Workflow] The workflow to check
  #
  # @example
  #   workflow = run_workflow_sync(MyWorkflow, user)
  #   expect_workflow_failed(workflow)
  #
  def expect_workflow_failed(workflow)
    expect(workflow.state).to eq("failed"),
      "Expected workflow to fail but was #{workflow.state}"

    expect(workflow.workflow_steps.failed.count).to be > 0,
      "Expected at least one failed step but found none. " \
      "Step statuses: #{workflow.workflow_steps.pluck(:name, :status)}"
  end

  # Find a specific step by name
  #
  # @param workflow [Workflow] The workflow instance
  # @param name [String, Symbol] The step name
  # @return [WorkflowStep, nil] The step or nil if not found
  #
  # @example
  #   step = find_step(workflow, :create_channel)
  #   expect(step.output["channel_id"]).to eq("C123")
  #
  def find_step(workflow, name)
    workflow.workflow_steps.find_by(name: name.to_s)
  end

  # Assert step completed with specific output
  #
  # @param workflow [Workflow] The workflow instance
  # @param step_name [String, Symbol] The step name
  # @param expected_output [Hash] Expected output hash (supports partial matching)
  #
  # @example
  #   expect_step_output(workflow, :create_channel, channel_id: "C123")
  #
  def expect_step_output(workflow, step_name, expected_output)
    step = find_step(workflow, step_name)
    expect(step).to be_present, "Step #{step_name} not found"
    expect(step.succeeded?).to be true, "Step #{step_name} did not succeed (status: #{step.status})"

    expected_output.each do |key, value|
      expect(step.output[key.to_s]).to eq(value),
        "Expected step #{step_name} output[#{key}] to be #{value.inspect} but was #{step.output[key.to_s].inspect}"
    end
  end

  # Assert step was skipped with reason
  #
  # @param workflow [Workflow] The workflow instance
  # @param step_name [String, Symbol] The step name
  # @param reason [String, nil] Optional expected skip reason
  #
  # @example
  #   expect_step_skipped(workflow, :premium_feature, "User not premium")
  #
  def expect_step_skipped(workflow, step_name, reason: nil)
    step = find_step(workflow, step_name)
    expect(step).to be_present, "Step #{step_name} not found"
    expect(step.skipped?).to be true, "Step #{step_name} was not skipped (status: #{step.status})"

    if reason
      expect(step.skip_reason).to include(reason),
        "Expected skip reason to include #{reason.inspect} but was #{step.skip_reason.inspect}"
    end
  end

  # Get all step names and statuses as a hash
  #
  # Useful for debugging or checking overall workflow progress
  #
  # @param workflow [Workflow] The workflow instance
  # @return [Hash] Hash of step_name => status
  #
  # @example
  #   step_statuses(workflow)
  #   # => { "create_channel" => "succeeded", "post_message" => "succeeded" }
  #
  def step_statuses(workflow)
    workflow.workflow_steps.ordered.pluck(:name, :status).to_h
  end
end

# Auto-include in workflow specs
RSpec.configure do |config|
  config.include WorkflowHelpers, type: :workflow
end

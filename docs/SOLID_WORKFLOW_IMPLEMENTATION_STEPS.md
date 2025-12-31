# SolidWorkflow Implementation Steps

Complete implementation guide for building SolidWorkflow from scratch. Follow these steps sequentially to build a production-ready workflow engine.

## Table of Contents

- [Phase 1: Database Setup](#phase-1-database-setup)
- [Phase 2: Core Models](#phase-2-core-models)
- [Phase 3: Basic Workflow Execution](#phase-3-basic-workflow-execution)
- [Phase 4: Orchestrator with Dependencies](#phase-4-orchestrator-with-dependencies)
- [Phase 5: Error Handling and Retries](#phase-5-error-handling-and-retries)
- [Phase 6: Advanced Features](#phase-6-advanced-features)
- [Phase 7: Observability](#phase-7-observability)
- [Phase 8: Performance and Safety](#phase-8-performance-and-safety)
- [Phase 9: Testing Infrastructure](#phase-9-testing-infrastructure)
- [Phase 10: Web UI (Optional)](#phase-10-web-ui-optional)
- [Gem Extraction Guide](#gem-extraction-guide)

---

## Phase 1: Database Setup

### Step 1.1: Create Migrations

Create three migration files:

**Migration 1: Create Workflows Table**

```ruby
# db/migrate/20250101000001_create_workflows.rb
class CreateWorkflows < ActiveRecord::Migration[7.0]
  def change
    create_table :workflows, id: :uuid do |t|
      t.string   :name,                null: false
      t.string   :workflow_class,      null: false
      t.string   :subject_type,        null: false
      t.uuid     :subject_id,          null: false
      t.string   :state,               null: false, default: "pending"
      t.jsonb    :context,             null: false, default: {}
      t.jsonb    :workflow_config,     default: {}
      t.datetime :started_at
      t.datetime :completed_at
      t.string   :cancelled_by
      t.text     :cancellation_reason
      t.timestamps

      t.index [:subject_type, :subject_id], name: "index_workflows_on_subject"
      t.index :state
      t.index :workflow_class
      t.index :created_at
      t.index [:state, :updated_at], name: "index_workflows_on_state_and_updated_at"
    end
  end
end
```

**Migration 2: Create Workflow Steps Table**

```ruby
# db/migrate/20250101000002_create_workflow_steps.rb
class CreateWorkflowSteps < ActiveRecord::Migration[7.0]
  def change
    create_table :workflow_steps, id: :uuid do |t|
      t.uuid       :workflow_id,   null: false
      t.string     :name,          null: false
      t.string     :status,        null: false, default: "pending"
      t.string     :depends_on,    array: true, default: []
      t.integer    :position
      t.integer    :attempts,      null: false, default: 0
      t.integer    :max_attempts,  default: 5
      t.datetime   :run_at
      t.datetime   :started_at
      t.datetime   :completed_at
      t.jsonb      :input,         null: false, default: {}
      t.jsonb      :output,        null: false, default: {}
      t.jsonb      :retry_config
      t.text       :last_error
      t.text       :skip_reason
      t.timestamps

      t.index :workflow_id, name: "index_workflow_steps_on_workflow_id"
      t.index [:workflow_id, :name], name: "index_workflow_steps_on_workflow_and_name"
      t.index [:workflow_id, :status], name: "index_workflow_steps_on_workflow_and_status"
      t.index :status
      t.index :run_at
    end

    add_foreign_key :workflow_steps, :workflows
  end
end
```

**Migration 3: Create Workflow Events Table**

```ruby
# db/migrate/20250101000003_create_workflow_events.rb
class CreateWorkflowEvents < ActiveRecord::Migration[7.0]
  def change
    create_table :workflow_events, id: :uuid do |t|
      t.uuid       :workflow_id,      null: false
      t.uuid       :workflow_step_id
      t.string     :event_type,       null: false
      t.jsonb      :metadata,         default: {}
      t.timestamp  :created_at,       null: false

      t.index :workflow_id, name: "index_workflow_events_on_workflow_id"
      t.index :workflow_step_id, name: "index_workflow_events_on_workflow_step_id"
      t.index [:workflow_id, :created_at], name: "index_workflow_events_on_workflow_and_created_at"
      t.index :event_type
      t.index :created_at
    end

    add_foreign_key :workflow_events, :workflows
    add_foreign_key :workflow_events, :workflow_steps
  end
end
```

### Step 1.2: Run Migrations

```bash
rails db:migrate
```

### Step 1.3: Verify Schema

```bash
rails db:schema:dump
# Verify schema.rb contains all three tables
```

---

## Phase 2: Core Models

Following 37signals patterns, we'll use concerns to break up model logic into focused, reusable modules.

### Step 2.1: Create Workflow Model (Thin)

```ruby
# app/models/workflow.rb
class Workflow < ApplicationRecord
  include Workflow::Stateable
  include Workflow::Eventable
  include Workflow::Orchestratable
  include Workflow::Cancellable

  belongs_to :subject, polymorphic: true
  has_many :workflow_steps, -> { order(:position) }, dependent: :destroy
  has_many :workflow_events, dependent: :destroy

  validates :name, :workflow_class, presence: true

  def workflow_klass
    @workflow_klass ||= workflow_class.constantize
  end
end
```

### Step 2.1a: Create Workflow::Stateable Concern

```ruby
# app/models/workflow/stateable.rb
module Workflow::Stateable
  extend ActiveSupport::Concern

  included do
    enum :state, {
      pending: "pending",
      running: "running",
      paused: "paused",
      succeeded: "succeeded",
      failed: "failed",
      cancelled: "cancelled"
    }

    scope :completed, -> { where(state: %w[succeeded failed cancelled]) }
    scope :active, -> { where(state: %w[pending running paused]) }
  end

  def transition_to!(new_state)
    update!(state: new_state, "#{new_state}_at": Time.current)
    record_event("workflow.#{new_state}")
  end

  def completed?
    succeeded? || failed? || cancelled?
  end

  def active?
    pending? || running?
  end
end
```

### Step 2.1b: Create Workflow::Eventable Concern

```ruby
# app/models/workflow/eventable.rb
module Workflow::Eventable
  extend ActiveSupport::Concern

  def record_event(event_type, step: nil, **metadata)
    workflow_events.create!(
      event_type: event_type,
      workflow_step: step,
      metadata: metadata
    )
  end

  def timeline
    workflow_events.order(:created_at).map do |event|
      {
        timestamp: event.created_at,
        type: event.event_type,
        step: event.workflow_step&.name,
        metadata: event.metadata
      }
    end
  end
end
```

### Step 2.1c: Create Workflow::Cancellable Concern

```ruby
# app/models/workflow/cancellable.rb
module Workflow::Cancellable
  extend ActiveSupport::Concern

  def cancel!(reason:, by:)
    transaction do
      update!(
        state: :cancelled,
        cancelled_by: by,
        cancellation_reason: reason,
        completed_at: Time.current
      )

      workflow_steps.where(status: :pending).update_all(status: :cancelled)
      record_event(WorkflowEvents::Workflow::CANCELLED, reason: reason, by: by)
    end
  end
end
```

### Step 2.1d: Create Workflow::Orchestratable Concern

Following 37signals pattern: no service objects, all logic in model concerns.

**Note**: Uses optimistic locking for high-throughput concurrent execution (no advisory locks).

```ruby
# app/models/workflow/orchestratable.rb
module Workflow::Orchestratable
  extend ActiveSupport::Concern

  # Main orchestration method
  def enqueue_next_steps
    reload
    steps = workflow_steps.reload.to_a

    return if completed? || paused?

    # Build step map for O(1) lookups
    step_map = steps.index_by(&:name)
    ready = steps.select { |s| s.ready_to_run?(step_map) }
    ready = apply_concurrency_limit(steps, ready)

    # Batch update inputs
    ready.each do |step|
      step.populate_input_data(steps)
    end

    # Track successfully updated steps for job enqueueing
    successfully_updated = []

    # Batch update all step inputs with optimistic locking
    WorkflowStep.transaction do
      ready.each do |step|
        next unless step.changed?

        # Optimistic locking: only update if status and updated_at haven't changed
        rows_updated = WorkflowStep.where(
          id: step.id,
          status: step.status_was,
          updated_at: step.updated_at_was
        ).update_all(
          input: step.input,
          updated_at: Time.current
        )

        successfully_updated << step if rows_updated > 0
      end
    end

    # Only enqueue jobs for steps that were successfully updated
    successfully_updated.each do |step|
      Workflows::RunStepJob.perform_later(step.id)
    end

    update_workflow_state(steps)
  end

  # Schedule with debounce
  def enqueue_next_steps_later
    Workflows::OrchestrateJob.set(wait: 1.second).perform_later(id)
  end

  private

    def apply_concurrency_limit(all_steps, ready_steps)
      max_concurrent = workflow_config.dig("max_concurrent_steps")
      return ready_steps unless max_concurrent

      running_count = all_steps.count(&:running?)
      available_slots = [max_concurrent - running_count, 0].max

      ready_steps.take(available_slots)
    end

    def update_workflow_state(steps)
      reload # Get fresh state

      if steps.all? { |s| s.succeeded? || s.skipped? }
        # Atomic transition to succeeded with optimistic locking
        current_updated_at = updated_at
        rows_updated = Workflow.where(
          id: id,
          state: [:pending, :running],
          updated_at: current_updated_at
        ).update_all(
          state: :succeeded,
          completed_at: Time.current,
          updated_at: Time.current
        )

        if rows_updated > 0
          reload
          record_event(WorkflowEvents::Workflow::SUCCEEDED)
        end

      elsif steps.any? { |s| s.failed? && s.attempts >= s.max_attempts }
        # Atomic transition to failed with optimistic locking
        current_updated_at = updated_at
        rows_updated = Workflow.where(
          id: id,
          state: [:pending, :running],
          updated_at: current_updated_at
        ).update_all(
          state: :failed,
          completed_at: Time.current,
          updated_at: Time.current
        )

        if rows_updated > 0
          reload
          record_event(WorkflowEvents::Workflow::FAILED)
        end

      elsif pending?
        # Atomic transition to running with optimistic locking
        current_updated_at = updated_at
        rows_updated = Workflow.where(
          id: id,
          state: :pending,
          updated_at: current_updated_at
        ).update_all(
          state: :running,
          started_at: Time.current,
          updated_at: Time.current
        )

        reload if rows_updated > 0
      end
    end
end
```

### Step 2.2: Create WorkflowStep Model (Thin)

```ruby
# app/models/workflow_step.rb
class WorkflowStep < ApplicationRecord
  include WorkflowStep::Statusable
  include WorkflowStep::Executable
  include WorkflowStep::Retryable
  include WorkflowStep::Dependencies

  belongs_to :workflow
  has_many :workflow_events, dependent: :destroy

  validates :name, :status, presence: true

  scope :ordered, -> { order(:position) }
end
```

### Step 2.2a: Create WorkflowStep::Statusable Concern

```ruby
# app/models/workflow_step/statusable.rb
module WorkflowStep::Statusable
  extend ActiveSupport::Concern

  included do
    enum :status, {
      pending: "pending",
      running: "running",
      succeeded: "succeeded",
      failed: "failed",
      skipped: "skipped",
      cancelled: "cancelled"
    }

    scope :pending, -> { where(status: :pending) }
    scope :running, -> { where(status: :running) }
    scope :completed, -> { where(status: %i[succeeded skipped]) }
    scope :failed, -> { where(status: :failed) }
    scope :in_progress, -> { where(status: :running) }
  end

  def completed?
    succeeded? || failed? || skipped? || cancelled?
  end
end
```

### Step 2.2b: Create WorkflowStep::Dependencies Concern

```ruby
# app/models/workflow_step/dependencies.rb
module WorkflowStep::Dependencies
  extend ActiveSupport::Concern

  def ready_to_run?(all_steps_or_map)
    return false unless pending?
    return false if run_at && run_at > Time.current

    # Support both array (legacy) and hash map (optimized) lookups
    step_map = all_steps_or_map.is_a?(Hash) ? all_steps_or_map : all_steps_or_map.index_by(&:name)

    depends_on.all? do |dep_name|
      dep_step = step_map[dep_name]
      dep_step && (dep_step.succeeded? || dep_step.skipped?)
    end
  end

  # Populate input data without saving (for batch updates)
  def populate_input_data(all_steps)
    input_data = {}
    depends_on.each do |dep_name|
      dep_step = all_steps.find { |s| s.name == dep_name }
      input_data[dep_name] = dep_step.output if dep_step
    end

    self.input = input_data if input_data.any?
  end

  # Legacy method for backward compatibility
  def populate_input!(all_steps)
    populate_input_data(all_steps)
    save! if changed?
  end
end
```

### Step 2.2c: Create WorkflowStep::Executable Concern

**Note**: Status transition to 'running' now handled by RunStepJob using optimistic locking.

```ruby
# app/models/workflow_step/executable.rb
module WorkflowStep::Executable
  extend ActiveSupport::Concern

  def execute!
    return if workflow.cancelled?
    return if succeeded? || cancelled?

    # Status transition to 'running' now handled by RunStepJob
    # This method assumes step is already in 'running' status

    # Execute the step
    runner = workflow.workflow_klass.new
    output = runner.run_step(
      name,
      workflow: workflow,
      step: self,
      input: input
    )

    # Atomic transition: running → succeeded with optimistic locking
    current_updated_at = updated_at
    rows_updated = WorkflowStep.where(
      id: id,
      status: :running,
      updated_at: current_updated_at
    ).update_all(
      status: :succeeded,
      output: output || {},
      completed_at: Time.current,
      updated_at: Time.current
    )

    # If update failed, step was cancelled/modified - reload and check
    if rows_updated == 0
      reload
      return if cancelled? # Cancelled during execution - exit gracefully
      raise "Step status changed unexpectedly during execution"
    end

    reload # Reload to get updated attributes
    workflow.record_event(WorkflowEvents::Step::SUCCEEDED, step: self)
  end

  def mark_failed!(error)
    update!(last_error: format_error(error))
    workflow.record_event(WorkflowEvents::Step::FAILED, step: self, error: error.message)

    if should_retry?
      schedule_retry!
    else
      update!(status: :failed, completed_at: Time.current)
    end
  end

  private

  def format_error(error)
    "#{error.class}: #{error.message}\n#{error.backtrace.first(5).join("\n")}"
  end
end
```

### Step 2.2d: Create WorkflowStep::Retryable Concern

```ruby
# app/models/workflow_step/retryable.rb
module WorkflowStep::Retryable
  extend ActiveSupport::Concern

  # Backoff strategy constants
  BACKOFF_EXPONENTIAL = "exponential"
  BACKOFF_LINEAR = "linear"
  BACKOFF_FIXED = "fixed"

  def should_retry?
    attempts < max_attempts
  end

  def schedule_retry!
    delay = calculate_backoff

    update!(
      status: :pending,
      run_at: Time.current + delay
    )

    workflow.record_event(WorkflowEvents::Step::RETRY_SCHEDULED, step: self, delay: delay, attempt: attempts)
  end

  def retry_now!
    transaction do
      update!(
        status: :pending,
        attempts: 0,
        last_error: nil,
        run_at: nil
      )

      workflow.record_event(WorkflowEvents::Step::MANUAL_RETRY, step: self)
    end

    workflow.enqueue_next_steps
  end

  def skip!(reason:)
    transaction do
      update!(
        status: :skipped,
        skip_reason: reason,
        completed_at: Time.current
      )

      workflow.record_event(WorkflowEvents::Step::MANUAL_SKIP, step: self, reason: reason)
    end

    workflow.enqueue_next_steps
  end

  private

  def calculate_backoff
    strategy = retry_config&.dig("backoff") || BACKOFF_EXPONENTIAL

    case strategy
    when BACKOFF_EXPONENTIAL
      [2**attempts, 300].min.seconds
    when BACKOFF_LINEAR
      [attempts * 30, 300].min.seconds
    when BACKOFF_FIXED
      (retry_config["backoff_seconds"] || 60).seconds
    else
      60.seconds
    end
  end
end
```

### Step 2.2e: Create WorkflowEvents Constants Module

All workflow event types are centralized in a constants module to prevent typos and enable IDE autocomplete.

```ruby
# app/models/concerns/workflow_events.rb
module WorkflowEvents
  # Workflow-level events
  module Workflow
    STARTED = "workflow.started"
    RUNNING = "workflow.running"
    SUCCEEDED = "workflow.succeeded"
    FAILED = "workflow.failed"
    CANCELLED = "workflow.cancelled"
  end

  # Step-level events
  module Step
    STARTED = "step.started"
    SUCCEEDED = "step.succeeded"
    FAILED = "step.failed"
    SKIPPED = "step.skipped"
    CANCELLED = "step.cancelled"
    RETRY_SCHEDULED = "step.retry_scheduled"
    MANUAL_RETRY = "step.manual_retry"
    MANUAL_SKIP = "step.manual_skip"
    RESET = "step.reset"
  end
end
```

**Event Naming Convention:**

Events follow the pattern `<scope>.<action>`:
- **Scopes:** `workflow` (workflow-level), `step` (step-level)
- **Actions:** Past tense for completed actions (`succeeded`, `failed`, `started`)
- **Format:** lowercase with underscores for multi-word actions (`retry_scheduled`)

**Usage:**

```ruby
# Instead of:
record_event("workflow.succeeded")

# Use:
record_event(WorkflowEvents::Workflow::SUCCEEDED)
```

### Step 2.3: Create WorkflowEvent Model

```ruby
# app/models/workflow_event.rb
class WorkflowEvent < ApplicationRecord
  # Associations
  belongs_to :workflow
  belongs_to :workflow_step, optional: true

  # Validations
  validates :event_type, presence: true

  # Scopes
  scope :workflow_level, -> { where(workflow_step_id: nil) }
  scope :step_level, -> { where.not(workflow_step_id: nil) }
end
```

### Step 2.4: Write Model Tests

```ruby
# spec/models/workflow_spec.rb
require 'rails_helper'

RSpec.describe Workflow, type: :model do
  describe "associations" do
    it { should belong_to(:subject) }
    it { should have_many(:workflow_steps).dependent(:destroy) }
    it { should have_many(:workflow_events).dependent(:destroy) }
  end

  describe "validations" do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:workflow_class) }
    it { should validate_presence_of(:state) }
  end

  describe "#workflow_klass" do
    it "returns the workflow class constant" do
      workflow = create(:workflow, workflow_class: "TestWorkflow")
      expect(workflow.workflow_klass).to eq(TestWorkflow)
    end
  end

  describe "#record_event" do
    it "creates a workflow event" do
      workflow = create(:workflow)
      expect {
        workflow.record_event("test.event", foo: "bar")
      }.to change(WorkflowEvent, :count).by(1)

      event = workflow.workflow_events.last
      expect(event.event_type).to eq("test.event")
      expect(event.metadata["foo"]).to eq("bar")
    end
  end
end
```

```ruby
# spec/models/workflow_step_spec.rb
require 'rails_helper'

RSpec.describe WorkflowStep, type: :model do
  describe "#ready_to_run?" do
    let(:workflow) { create(:workflow) }
    let(:step_a) { create(:workflow_step, workflow: workflow, name: "step_a", status: "succeeded") }
    let(:step_b) { create(:workflow_step, workflow: workflow, name: "step_b", status: "pending", depends_on: ["step_a"]) }
    let(:step_c) { create(:workflow_step, workflow: workflow, name: "step_c", status: "pending", depends_on: ["step_a", "step_b"]) }

    it "returns true when no dependencies" do
      step = create(:workflow_step, workflow: workflow, status: :pending, depends_on: [])
      expect(step.ready_to_run?([])).to be true
    end

    it "returns true when all dependencies succeeded" do
      all_steps = [step_a, step_b]
      expect(step_b.ready_to_run?(all_steps)).to be true
    end

    it "returns false when dependencies not met" do
      all_steps = [step_a, step_b, step_c]
      expect(step_c.ready_to_run?(all_steps)).to be false
    end

    it "returns false when run_at is in future" do
      step = create(:workflow_step, workflow: workflow, status: :pending, run_at: 1.hour.from_now)
      expect(step.ready_to_run?([])).to be false
    end

    it "returns false when status is not pending" do
      step = create(:workflow_step, workflow: workflow, status: :running)
      expect(step.ready_to_run?([])).to be false
    end

    it "returns true when dependency is skipped" do
      step_a.update!(status: :skipped)
      all_steps = [step_a, step_b]
      expect(step_b.ready_to_run?(all_steps)).to be true
    end
  end
end
```

---

## Phase 3: Basic Workflow Execution

### Step 3.1: Create Workflows::Base Class

```ruby
# app/workflows/base.rb
class Workflows::Base
  class << self
    # Define workflow name
    def workflow_name(val = nil)
      @workflow_name = val if val
      @workflow_name || name
    end

    # Define workflow config
    def workflow_config(val = nil)
      @workflow_config = val if val
      @workflow_config || {}
    end

    # Define a step
    def step(name, depends_on: [], retry_config: nil)
      steps << {
        name: name.to_s,
        depends_on: Array(depends_on).map(&:to_s),
        retry_config: retry_config
      }
    end

    # Get all steps
    def steps
      @steps ||= []
    end

    # Start a workflow (async)
    def start!(subject, context: {})
      wf = create_workflow!(subject, context)
      wf.enqueue_next_steps
      wf
    end

    private

    def create_workflow!(subject, context)
      wf = Workflow.create!(
        name: workflow_name,
        workflow_class: name,
        subject_type: subject.class.name,
        subject_id: subject.id,
        context: context,
        state: "pending",
        workflow_config: workflow_config
      )

      # Create steps
      steps.each_with_index do |step_def, index|
        wf.workflow_steps.create!(
          name: step_def[:name],
          depends_on: step_def[:depends_on],
          status: "pending",
          position: index,
          retry_config: step_def[:retry_config] || default_retry_config,
          max_attempts: step_def.dig(:retry_config, :max_attempts) || 5
        )
      end

      wf.record_event(WorkflowEvents::Workflow::STARTED)
      wf
    end

    def default_retry_config
      { max_attempts: 5, backoff: WorkflowStep::Retryable::BACKOFF_EXPONENTIAL }
    end
  end

  # Run a specific step
  def run_step(step_name, workflow:, step:, input: {})
    raise "Unknown step: #{step_name}" unless respond_to?(step_name)
    public_send(step_name, workflow: workflow, step: step, input: input)
  end
end
```

### Step 3.2: Orchestration Logic

The orchestration logic is now in the `Workflow::Orchestratable` concern (see Step 2.1d).

No separate service class needed - following 37signals pattern of keeping logic in model concerns.

### Step 3.3: Create Step Job

The job is lightweight and uses optimistic locking for atomic step claiming:

**Note**: Uses atomic claim pattern with optimistic locking (no pessimistic locks).

```ruby
# app/jobs/workflows/run_step_job.rb
class Workflows::RunStepJob < ApplicationJob
  queue_as :workflows

  def perform(step_id)
    start_time = Time.current

    @step = WorkflowStep.find(step_id)
    @workflow = @step.workflow

    # Early returns for already-processed states (idempotency)
    return if @step.succeeded? || @step.cancelled? || @step.running?
    return if @workflow.cancelled?

    # Atomic claim: try to transition pending → running with optimistic locking
    current_updated_at = @step.updated_at
    rows_updated = WorkflowStep.where(
      id: @step.id,
      status: :pending,
      updated_at: current_updated_at
    ).update_all(
      status: :running,
      attempts: @step.attempts + 1,
      started_at: Time.current,
      updated_at: Time.current
    )

    # Another worker won the race - exit gracefully
    return if rows_updated == 0

    # Reload to get updated attributes
    @step.reload
    @workflow.reload

    # Double-check workflow not cancelled after claim
    if @workflow.cancelled?
      @step.update!(status: :cancelled, completed_at: Time.current)
      return
    end

    @workflow.record_event(WorkflowEvents::Step::STARTED, step: @step)

    Rails.logger.info({
      event: "workflow.step.started",
      workflow_id: @workflow.id,
      workflow_class: @workflow.workflow_class,
      step_id: @step.id,
      step_name: @step.name,
      attempt: @step.attempts,
      max_attempts: @step.max_attempts,
      subject_type: @workflow.subject_type,
      subject_id: @workflow.subject_id
    })

    @step.execute!

  rescue StandardError => e
    @step.mark_failed!(e)
    raise
  ensure
    # Always trigger orchestration
    @workflow.enqueue_next_steps_later if @workflow
  end
end
```

All execution logic is in the `WorkflowStep::Executable` and `WorkflowStep::Retryable` concerns. The job focuses on atomic claiming and coordination.

### Step 3.4: Create Example Workflow

```ruby
# app/workflows/test_workflow.rb
class TestWorkflow < Workflows::Base
  workflow_name "test.workflow.v1"

  step :step_one
  step :step_two, depends_on: [:step_one]
  step :step_three, depends_on: [:step_one, :step_two]

  def step_one(workflow:, step:, input:)
    { result: "step_one_complete" }
  end

  def step_two(workflow:, step:, input:)
    value = input.dig("step_one", "result")
    { result: "step_two_complete", previous: value }
  end

  def step_three(workflow:, step:, input:)
    { result: "step_three_complete" }
  end
end
```

### Step 3.5: Test Basic Execution

```ruby
# spec/workflows/test_workflow_spec.rb
require 'rails_helper'

RSpec.describe TestWorkflow do
  let(:subject_record) { create(:incident) }

  it "executes all steps in order" do
    workflow = TestWorkflow.start!(subject_record)

    # Process jobs
    perform_enqueued_jobs

    workflow.reload
    expect(workflow.state).to eq("succeeded")
    expect(workflow.workflow_steps.pluck(:status).uniq).to eq(["succeeded"])
  end

  it "passes data between steps" do
    workflow = TestWorkflow.start!(subject_record)
    perform_enqueued_jobs

    step_two = workflow.workflow_steps.find_by(name: "step_two")
    expect(step_two.input.dig("step_one", "result")).to eq("step_one_complete")
    expect(step_two.output["previous"]).to eq("step_one_complete")
  end

  it "executes steps with dependencies in correct order" do
    workflow = TestWorkflow.start!(subject_record)

    execution_order = []
    allow_any_instance_of(TestWorkflow).to receive(:step_one) do |*args|
      execution_order << "step_one"
      { result: "step_one_complete" }
    end
    allow_any_instance_of(TestWorkflow).to receive(:step_two) do |*args|
      execution_order << "step_two"
      { result: "step_two_complete" }
    end
    allow_any_instance_of(TestWorkflow).to receive(:step_three) do |*args|
      execution_order << "step_three"
      { result: "step_three_complete" }
    end

    perform_enqueued_jobs

    expect(execution_order.first).to eq("step_one")
    expect(execution_order.last).to eq("step_three")
  end
end
```

---

## Phase 4: Orchestrator with Dependencies

### Step 4.1: Add Parallel Execution Support

The current orchestrator already supports parallel execution through the DAG. Test it:

```ruby
# app/workflows/parallel_workflow.rb
class ParallelWorkflow < Workflows::Base
  workflow_name "parallel.test.v1"

  step :start_step
  step :parallel_a, depends_on: [:start_step]
  step :parallel_b, depends_on: [:start_step]
  step :parallel_c, depends_on: [:start_step]
  step :final_step, depends_on: [:parallel_a, :parallel_b, :parallel_c]

  def start_step(workflow:, step:, input:)
    { started_at: Time.current }
  end

  def parallel_a(workflow:, step:, input:)
    { result: "a" }
  end

  def parallel_b(workflow:, step:, input:)
    { result: "b" }
  end

  def parallel_c(workflow:, step:, input:)
    { result: "c" }
  end

  def final_step(workflow:, step:, input:)
    results = [
      input.dig("parallel_a", "result"),
      input.dig("parallel_b", "result"),
      input.dig("parallel_c", "result")
    ]
    { all_results: results }
  end
end
```

### Step 4.2: Test Parallel Execution

```ruby
# spec/workflows/parallel_workflow_spec.rb
require 'rails_helper'

RSpec.describe ParallelWorkflow do
  let(:subject_record) { create(:incident) }

  it "executes parallel steps simultaneously" do
    workflow = ParallelWorkflow.start!(subject_record)

    # After start_step completes, all 3 parallel steps should be ready
    perform_enqueued_jobs(only: RunWorkflowStepJob) do |job|
      step = WorkflowStep.find(job.arguments.first)
      break if step.name == "start_step"
    end

    workflow.reload
    pending_steps = workflow.workflow_steps.where(status: "pending").pluck(:name)
    expect(pending_steps).to match_array(["parallel_a", "parallel_b", "parallel_c"])
  end

  it "waits for all parallel steps before final step" do
    workflow = ParallelWorkflow.start!(subject_record)
    perform_enqueued_jobs

    final_step = workflow.workflow_steps.find_by(name: "final_step")
    expect(final_step.output["all_results"]).to match_array(["a", "b", "c"])
  end
end
```

### Step 4.3: Concurrency Limiting

Concurrency limiting is already implemented in the `Workflow::Orchestratable` concern (see Step 2.1d).

The `apply_concurrency_limit` private method respects the `max_concurrent_steps` config.

---

## Phase 5: Error Handling and Retries

### Step 5.1: Test Retry Logic

Already implemented in RunWorkflowStepJob. Add comprehensive tests:

```ruby
# spec/jobs/run_workflow_step_job_spec.rb
require 'rails_helper'

RSpec.describe RunWorkflowStepJob do
  let(:workflow) { create(:workflow, workflow_class: "TestWorkflow") }
  let(:step) { create(:workflow_step, workflow: workflow, name: "failing_step", max_attempts: 3) }

  before do
    allow_any_instance_of(TestWorkflow).to receive(:failing_step).and_raise(StandardError, "Test error")
  end

  it "retries failed steps with exponential backoff" do
    expect {
      described_class.perform_now(step.id)
    }.to have_enqueued_job(described_class).with(step.id)

    step.reload
    expect(step.status).to eq("pending")
    expect(step.attempts).to eq(1)
    expect(step.last_error).to include("StandardError: Test error")
  end

  it "fails after max attempts" do
    step.update!(attempts: 2)

    described_class.perform_now(step.id)

    step.reload
    expect(step.status).to eq("failed")
    expect(step.attempts).to eq(3)
  end

  it "uses custom retry config" do
    step.update!(retry_config: { backoff: "fixed", backoff_seconds: 10 })

    described_class.perform_now(step.id)

    # Check job was scheduled with correct delay
    expect(enqueued_jobs.last[:at]).to be_within(1.second).of(Time.current + 10.seconds)
  end
end
```

### Step 5.2: Add Idempotency Helpers

```ruby
# app/workflows/concerns/idempotent_steps.rb
module IdempotentSteps
  # Check if value exists, return or execute block
  def idempotent_check(value, &block)
    return { value: value } if value.present?
    block.call
  end

  # Find or create external resource
  def find_or_create_external(identifier, find_method, create_method)
    # Check DB first
    existing = find_method.call
    return existing if existing

    # Create new
    create_method.call
  end
end

# Include in Workflows::Base
class Workflows::Base
  include IdempotentSteps
end
```

### Step 5.3: Create Example with Idempotency

```ruby
# app/workflows/slack_channel_workflow.rb
class SlackChannelWorkflow < Workflows::Base
  workflow_name "slack.channel.create.v1"

  step :create_channel
  step :post_message, depends_on: [:create_channel]

  def create_channel(workflow:, step:, input:)
    incident = workflow.subject

    # Idempotency: check if already created
    return { channel_id: incident.slack_channel_id } if incident.slack_channel_id

    # Idempotency: check if exists in Slack
    channel_name = "inc-#{incident.id}"
    existing = SlackClient.find_channel_by_name(channel_name)
    if existing
      incident.update!(slack_channel_id: existing)
      return { channel_id: existing }
    end

    # Create new
    channel_id = SlackClient.create_channel(channel_name)
    incident.update!(slack_channel_id: channel_id)

    { channel_id: channel_id }
  end

  def post_message(workflow:, step:, input:)
    incident = workflow.subject
    channel_id = input.dig("create_channel", "channel_id")

    # Idempotency: check if already posted
    return { ts: incident.initial_message_ts } if incident.initial_message_ts

    # Post message
    response = SlackClient.post_message(channel_id, "Incident created")
    incident.update!(initial_message_ts: response["ts"])

    { ts: response["ts"] }
  end
end
```

---

## Phase 6: Advanced Features

### Step 6.1: Add Cancellation Support

```ruby
# app/models/workflow.rb
class Workflow < ApplicationRecord
  # ... existing code ...

  def cancel!(reason:, by:)
    transaction do
      update!(
        state: "cancelled",
        cancelled_by: by,
        cancellation_reason: reason,
        completed_at: Time.current
      )

      # Cancel all pending steps
      workflow_steps.where(status: "pending").update_all(status: "cancelled")

      record_event(WorkflowEvents::Workflow::CANCELLED, reason: reason, by: by)
    end
  end
end
```

### Step 6.2: Test Cancellation

```ruby
# spec/models/workflow_spec.rb
RSpec.describe Workflow do
  describe "#cancel!" do
    let(:workflow) { create(:workflow, state: "running") }
    let!(:pending_step) { create(:workflow_step, workflow: workflow, status: "pending") }
    let!(:running_step) { create(:workflow_step, workflow: workflow, status: "running") }

    it "cancels workflow and pending steps" do
      workflow.cancel!(reason: "Test cancellation", by: "admin@example.com")

      expect(workflow.state).to eq("cancelled")
      expect(workflow.cancelled_by).to eq("admin@example.com")
      expect(workflow.cancellation_reason).to eq("Test cancellation")

      expect(pending_step.reload.status).to eq("cancelled")
      expect(running_step.reload.status).to eq("running")  # Don't cancel running
    end

    it "records cancellation event" do
      expect {
        workflow.cancel!(reason: "Test", by: "admin")
      }.to change(WorkflowEvent, :count).by(1)

      event = workflow.workflow_events.last
      expect(event.event_type).to eq("workflow.cancelled")
    end
  end
end
```

### Step 6.3: Add Skip Support

```ruby
# app/models/workflow_step.rb
class WorkflowStep < ApplicationRecord
  # ... existing code ...

  def skip!(reason:)
    update!(
      status: "skipped",
      skip_reason: reason,
      completed_at: Time.current
    )

    workflow.record_event(WorkflowEvents::Step::SKIPPED, step: self, reason: reason)
  end
end
```

### Step 6.4: Create Workflow with Conditional Steps

```ruby
# app/workflows/conditional_workflow.rb
class ConditionalWorkflow < Workflows::Base
  workflow_name "conditional.test.v1"

  step :check_eligibility
  step :premium_action, depends_on: [:check_eligibility]
  step :standard_action, depends_on: [:check_eligibility]

  def check_eligibility(workflow:, step:, input:)
    user = workflow.subject
    { is_premium: user.premium? }
  end

  def premium_action(workflow:, step:, input:)
    is_premium = input.dig("check_eligibility", "is_premium")

    unless is_premium
      step.skip!(reason: "User is not premium")
      return { skipped: true }
    end

    # Premium logic here
    { result: "premium_complete" }
  end

  def standard_action(workflow:, step:, input:)
    # Always runs
    { result: "standard_complete" }
  end
end
```

### Step 6.5: Manual Retry/Skip

Manual retry and skip functionality is already implemented in the `WorkflowStep::Retryable` concern (see Step 2.2d).

**When to use:**

- **Retry:** Transient failures now resolved (API back up, credentials fixed)
- **Skip:** Non-critical step failing, want to complete workflow anyway

The methods are available on any WorkflowStep instance:
- `step.retry_now!` - Resets the step to pending and triggers orchestration
- `step.skip!(reason: "...")` - Marks step as skipped and continues workflow

**Test manual retry/skip:**

```ruby
# spec/models/workflow_step_spec.rb
RSpec.describe WorkflowStep do
  describe "#retry_now!" do
    let(:workflow) { create(:workflow) }
    let(:step) { create(:workflow_step, workflow: workflow, status: "failed", attempts: 3, last_error: "Error") }

    it "resets step for retry" do
      step.retry_now!

      expect(step.status).to eq("pending")
      expect(step.attempts).to eq(0)
      expect(step.last_error).to be_nil
      expect(step.run_at).to be_nil
    end

    it "records manual retry event" do
      expect {
        step.retry_now!
      }.to change(WorkflowEvent, :count).by(1)

      event = workflow.workflow_events.last
      expect(event.event_type).to eq("step.manual_retry")
    end

    it "triggers orchestration" do
      expect(workflow).to receive(:enqueue_next_steps)
      step.retry_now!
    end
  end

  describe "#skip!" do
    let(:workflow) { create(:workflow) }
    let(:step) { create(:workflow_step, workflow: workflow, status: :failed) }

    it "marks step as skipped with reason" do
      step.skip!(reason: "Not critical, can skip")

      expect(step.skipped?).to be true
      expect(step.skip_reason).to eq("Not critical, can skip")
      expect(step.completed_at).to be_present
    end

    it "records skip event" do
      expect {
        step.skip!(reason: "Test skip")
      }.to change(WorkflowEvent, :count).by(1)

      event = workflow.workflow_events.last
      expect(event.event_type).to eq("step.manual_skip")
      expect(event.metadata["reason"]).to eq("Test skip")
    end

    it "triggers orchestration to continue workflow" do
      expect(workflow).to receive(:enqueue_next_steps)
      step.skip!(reason: "Skip test")
    end
  end
end
```

**UI integration example:**

```ruby
# app/controllers/workflows/workflow_steps_controller.rb
module Workflows
  class WorkflowStepsController < ApplicationController
    def retry
      step = WorkflowStep.find(params[:id])
      step.retry_now!
      redirect_to workflows_workflow_path(step.workflow), notice: "Step retry scheduled"
    end

    def skip
      step = WorkflowStep.find(params[:id])
      step.skip!(reason: params[:reason] || "Manually skipped by admin")
      redirect_to workflows_workflow_path(step.workflow), notice: "Step skipped"
    end
  end
end
```

---

## Phase 7: Observability

### Step 7.1: Events Already Implemented

Events are already being recorded in:

- `workflow.record_event()` calls
- `Workflows::RunStepJob` (start, success, failure)
- `Workflow::Orchestratable` concern (workflow state changes)

### Step 7.2: Add Workflow Metrics Concern

Following the 37signals pattern of no service objects, add metrics as a concern:

```ruby
# app/models/workflow/metrics.rb
module Workflow::Metrics
  extend ActiveSupport::Concern

  class_methods do
    def summary(time_range: 1.hour.ago..)
      workflows = where(created_at: time_range)

      {
        total: workflows.count,
        by_state: workflows.group(:state).count,
        by_workflow_class: workflows.group(:workflow_class).count,
        avg_duration: average_duration(time_range),
        stuck_count: stuck.count
      }
    end

    def average_duration(time_range: 1.day.ago..)
      where(state: :succeeded)
        .where(created_at: time_range)
        .average("EXTRACT(EPOCH FROM (completed_at - created_at))")
        &.to_f
        &.round(2)
    end

    def failure_rate(workflow_class: nil, time_range: 24.hours.ago..)
      scope = where(created_at: time_range)
      scope = scope.where(workflow_class: workflow_class) if workflow_class

      total = scope.count
      return 0.0 if total.zero?

      failed = scope.where(state: :failed).count
      (failed.to_f / total * 100).round(2)
    end

    def state_summary(time_range: 1.hour.ago..)
      where(created_at: time_range).group(:state).count
    end
  end

  # Instance methods
  def duration
    return nil unless completed_at
    completed_at - created_at
  end

  def stuck?
    active? && updated_at < 30.minutes.ago
  end
end
```

Include in Workflow model:

```ruby
# app/models/workflow.rb
class Workflow < ApplicationRecord
  include Workflow::Stateable
  include Workflow::Eventable
  include Workflow::Orchestratable
  include Workflow::Cancellable
  include Workflow::Metrics  # Add this

  # ... rest of model
end
```

### Step 7.3: Add WorkflowStep Metrics Concern

```ruby
# app/models/workflow_step/metrics.rb
module WorkflowStep::Metrics
  extend ActiveSupport::Concern

  class_methods do
    def step_stats(workflow_class: nil, time_range: 1.hour.ago..)
      scope = joins(:workflow).where(workflows: { created_at: time_range })
      scope = scope.where(workflows: { workflow_class: workflow_class }) if workflow_class

      scope.group(:name, :status).count
    end

    def step_failure_rates(time_range: 24.hours.ago..)
      scope = where(created_at: time_range)
      totals = scope.group(:name).count
      failures = scope.where(status: :failed).group(:name).count

      totals.transform_values do |total|
        step_name = totals.key(total)
        failed_count = failures[step_name] || 0
        total.zero? ? 0.0 : (failed_count.to_f / total * 100).round(2)
      end
    end

    def average_step_durations(time_range: 24.hours.ago..)
      where(status: :succeeded)
        .where(created_at: time_range)
        .where.not(started_at: nil, completed_at: nil)
        .group(:name)
        .average("EXTRACT(EPOCH FROM (completed_at - started_at))")
        .transform_values { |v| v&.to_f&.round(2) }
    end
  end

  def duration
    return nil unless started_at && completed_at
    completed_at - started_at
  end
end
```

Include in WorkflowStep model:

```ruby
# app/models/workflow_step.rb
class WorkflowStep < ApplicationRecord
  include WorkflowStep::Statusable
  include WorkflowStep::Executable
  include WorkflowStep::Retryable
  include WorkflowStep::Dependencies
  include WorkflowStep::Metrics  # Add this

  # ... rest of model
end
```

### Step 7.4: Add Logging

```ruby
# app/jobs/workflows/run_step_job.rb
class Workflows::RunStepJob < ApplicationJob
  # ... existing code ...

  def perform(step_id)
    @step = WorkflowStep.lock.find(step_id)
    @workflow = @step.workflow.reload

    Rails.logger.info(
      "Starting workflow step",
      workflow_id: @workflow.id,
      workflow_class: @workflow.workflow_class,
      step_name: @step.name,
      attempt: @step.attempts + 1
    )

    # ... rest of method ...

  rescue StandardError => e
    Rails.logger.error(
      "Workflow step failed",
      workflow_id: @workflow.id,
      step_name: @step.name,
      error: e.message,
      backtrace: e.backtrace.first(5)
    )
    handle_failure(e)
  end
end
```

---

## Phase 8: Performance and Safety

### Step 8.1: Optimistic Locking for Scalability

**Important**: SolidWorkflow uses optimistic locking instead of advisory locks for high-throughput concurrent execution.

The implementation (already in `Workflow::Orchestratable` and `Workflows::RunStepJob` - see Steps 2.1d and 3.3) uses PostgreSQL's `UPDATE ... WHERE` pattern to prevent race conditions without holding locks.

**Key points**:
- **No advisory locks** - Allows 1000s of concurrent workflows without lock contention
- **Atomic updates** - Uses `WHERE id=X AND status=Y AND updated_at=Z` pattern
- **Graceful failures** - If concurrent update fails, operation is skipped (another process won)
- **Step idempotency required** - Steps MUST be idempotent since retries can occur

**Benefits over advisory locks**:
- Scales to 10,000+ concurrent workflows
- No connection pool exhaustion from long-held locks
- No deadlock risk
- Better database utilization

**Trade-off**:
- Steps must be carefully designed to be idempotent (documented in SOLID_WORKFLOW.md)

### Step 8.2: Add Debounced Orchestrator Job

```ruby
# app/jobs/workflows/orchestrate_job.rb
class Workflows::OrchestrateJob < ApplicationJob
  queue_as :workflows

  # Prevent duplicate jobs
  unique_for: 1.second, on_conflict: :skip  # Using solid_queue unique jobs

  def perform(workflow_id)
    workflow = Workflow.find(workflow_id)
    workflow.enqueue_next_steps
  end
end
```

Update the step job to use debounced orchestration:

```ruby
# app/jobs/workflows/run_step_job.rb
class Workflows::RunStepJob < ApplicationJob
  # ... existing code ...

  def perform(step_id)
    # ... existing code ...
  ensure
    # Use debounced orchestration
    @workflow.enqueue_next_steps_later if @workflow
  end
end
```

### Step 8.3: Add Sweeper Job

```ruby
# app/jobs/workflow_sweeper_job.rb
class WorkflowSweeperJob < ApplicationJob
  queue_as :workflows

  def perform
    sweep_stuck_workflows
    sweep_orphaned_steps
  end

  private

  def sweep_stuck_workflows
    Workflow.stuck.find_each do |workflow|
      Rails.logger.info({ event: "workflow.sweeper.resuming", workflow_id: workflow.id })
      workflow.enqueue_next_steps
    end
  end

  def sweep_orphaned_steps
    WorkflowStep.orphaned.find_each do |step|
      Rails.logger.warn({ event: "workflow.sweeper.resetting_orphan", step_id: step.id })

      step.update!(
        status: "pending",
        last_error: "Step was running but worker appears to have crashed (reset by sweeper)"
      )

      step.workflow.record_event(WorkflowEvents::Step::RESET, step: step, reason: "sweeper")
    end
  end
end
```

### Step 8.4: Schedule Sweeper

```ruby
# config/initializers/solid_queue.rb (or use whenever gem)
# Schedule WorkflowSweeperJob to run every 5 minutes

# Using Solid Queue recurring tasks:
# config/queue.yml
production:
  dispatchers:
    - polling_interval: 1
      batch_size: 500
  workers:
    - queues: workflows
      threads: 5
  recurring:
    workflow_sweeper:
      class: WorkflowSweeperJob
      schedule: "*/5 * * * *"  # Every 5 minutes
```

---

## Phase 9: Testing Infrastructure

### Step 9.1: Add Synchronous Test Helper

Add `start_inline!` method to `Workflows::Base` for synchronous execution:

```ruby
# app/workflows/base.rb
class Workflows::Base
  class << self
    # Start a workflow asynchronously (default)
    def start!(subject, context: {})
      wf = create_workflow!(subject, context)
      wf.enqueue_next_steps
      wf
    end

    # Start workflow synchronously (for tests and debugging)
    def start_inline!(subject, context: {})
      wf = create_workflow!(subject, context)

      max_iterations = 100  # Prevent infinite loops
      iteration = 0

      loop do
        iteration += 1
        raise "Workflow exceeded max iterations (#{max_iterations})" if iteration > max_iterations

        wf.reload
        steps = wf.workflow_steps.reload.to_a

        # Find ready steps
        ready = steps.select { |s| s.ready_to_run?(steps) }
        break if ready.empty?

        # Execute ready steps synchronously
        ready.each do |step|
          step.populate_input!(steps)
          Workflows::RunStepJob.new.perform(step.id)
        end

        # Update workflow state
        wf.enqueue_next_steps

        wf.reload
        break if wf.completed?
      end

      wf.reload
    end

    # ... rest of class
  end
end
```

**Usage:**
- `start!` - Always async (production, console, everywhere)
- `start_inline!` - Explicitly synchronous (tests, debugging)

### Step 9.2: Create Test Helpers Module

Create comprehensive test helpers in `spec/support/workflow_helpers.rb`:

```ruby
# spec/support/workflow_helpers.rb
module WorkflowHelpers
  # Run workflow synchronously
  def run_workflow_sync(workflow_class, subject, context: {})
    workflow_class.start_inline!(subject, context: context)
  end

  # Assertions
  def expect_workflow_succeeded(workflow)
    expect(workflow.state).to eq("succeeded"),
      "Expected workflow to succeed but was #{workflow.state}"
    expect(workflow.workflow_steps.pluck(:status).uniq).to match_array(%w[succeeded skipped])
  end

  def expect_workflow_failed(workflow)
    expect(workflow.state).to eq("failed"),
      "Expected workflow to fail but was #{workflow.state}"
    expect(workflow.workflow_steps.failed.count).to be > 0
  end

  # Finders
  def find_step(workflow, name)
    workflow.workflow_steps.find_by(name: name.to_s)
  end

  # Step assertions
  def expect_step_output(workflow, step_name, expected_output)
    step = find_step(workflow, step_name)
    expect(step).to be_present
    expect(step.succeeded?).to be true

    expected_output.each do |key, value|
      expect(step.output[key.to_s]).to eq(value)
    end
  end

  def expect_step_skipped(workflow, step_name, reason: nil)
    step = find_step(workflow, step_name)
    expect(step).to be_present
    expect(step.skipped?).to be true
    expect(step.skip_reason).to include(reason) if reason
  end

  # Debug helper
  def step_statuses(workflow)
    workflow.workflow_steps.ordered.pluck(:name, :status).to_h
  end
end

RSpec.configure do |config|
  config.include WorkflowHelpers, type: :workflow
end
```

### Step 9.3: Create Factory

```ruby
# spec/factories/workflows.rb
FactoryBot.define do
  factory :workflow do
    name { "test.workflow.v1" }
    workflow_class { "TestWorkflow" }
    association :subject, factory: :incident
    state { :pending }
    context { {} }
  end

  factory :workflow_step do
    association :workflow
    name { "test_step" }
    status { :pending }
    depends_on { [] }
    position { 0 }
    attempts { 0 }
    max_attempts { 5 }
    input { {} }
    output { {} }
  end

  factory :workflow_event do
    association :workflow
    event_type { "test.event" }
    metadata { {} }
  end
end
```

### Step 9.4: Integration Test Example

```ruby
# spec/workflows/incident_creation_workflow_spec.rb
require 'rails_helper'

RSpec.describe IncidentCreationWorkflow, type: :workflow do
  let(:incident) { create(:incident) }
  let(:context) do
    {
      slack_team_id: "T123",
      severity: "high"
    }
  end

  before do
    # Mock external services
    allow(SlackClient).to receive(:create_channel).and_return("C123")
    allow(SlackClient).to receive(:post_message).and_return({ "ts" => "123.456" })
    allow(SlackClient).to receive(:invite_users).and_return(true)
  end

  it "creates complete incident workflow" do
    workflow = run_workflow_sync(described_class, incident, context: context)

    expect_workflow_succeeded(workflow)

    # Verify state changes
    expect(incident.reload.slack_channel_id).to eq("C123")
    expect(incident.initial_message_ts).to eq("123.456")

    # Verify step outputs
    channel_step = find_step(workflow, "create_slack_channel")
    expect(channel_step.output["channel_id"]).to eq("C123")

    message_step = find_step(workflow, "post_initial_message")
    expect(message_step.output["ts"]).to eq("123.456")
  end

  it "handles Slack API failures with retries" do
    call_count = 0
    allow(SlackClient).to receive(:create_channel) do
      call_count += 1
      raise Slack::Web::Api::Errors::SlackError, "rate_limited" if call_count < 3
      "C123"
    end

    workflow = run_workflow_sync(described_class, incident, context: context)

    expect_workflow_succeeded(workflow)
    expect(call_count).to eq(3)

    # Verify retry tracking
    channel_step = find_step(workflow, "create_slack_channel")
    expect(channel_step.attempts).to eq(3)
  end

  it "is idempotent when retried" do
    incident.update!(slack_channel_id: "C123", initial_message_ts: "123.456")

    # Should not call external APIs
    expect(SlackClient).not_to receive(:create_channel)
    expect(SlackClient).not_to receive(:post_message)

    workflow = run_workflow_sync(described_class, incident, context: context)
    expect_workflow_succeeded(workflow)
  end
end
```

---

## Phase 10: Web UI (Optional)

### Step 10.1: Install Mission Control

```ruby
# Gemfile
gem "mission_control-jobs"
```

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount MissionControl::Jobs::Engine, at: "/jobs"

  # Custom workflow routes
  namespace :workflows do
    resources :workflows, only: [:index, :show] do
      member do
        post :cancel
        post :retry
      end
    end
  end
end
```

### Step 10.2: Create Workflows Controller

```ruby
# app/controllers/workflows/workflows_controller.rb
module Workflows
  class WorkflowsController < ApplicationController
    def index
      @workflows = Workflow.order(created_at: :desc).page(params[:page])
      @stats = WorkflowMetrics.summary
    end

    def show
      @workflow = Workflow.find(params[:id])
      @steps = @workflow.workflow_steps.order(:position)
      @events = @workflow.workflow_events.order(:created_at)
    end

    def cancel
      @workflow = Workflow.find(params[:id])
      @workflow.cancel!(
        reason: params[:reason] || "Cancelled by user",
        by: current_user.email
      )
      redirect_to workflows_workflow_path(@workflow), notice: "Workflow cancelled"
    end

    def retry
      @workflow = Workflow.find(params[:id])
      @workflow.enqueue_next_steps
      redirect_to workflows_workflow_path(@workflow), notice: "Workflow retry scheduled"
    end
  end
end
```

### Step 10.3: Create Views

```erb
<!-- app/views/workflows/workflows/index.html.erb -->
<h1>Workflows</h1>

<div class="stats">
  <div>Total: <%= @stats[:total] %></div>
  <div>Running: <%= @stats[:by_state]["running"] || 0 %></div>
  <div>Succeeded: <%= @stats[:by_state]["succeeded"] || 0 %></div>
  <div>Failed: <%= @stats[:by_state]["failed"] || 0 %></div>
  <div>Avg Duration: <%= @stats[:avg_duration]&.round(2) %>s</div>
</div>

<table>
  <thead>
    <tr>
      <th>ID</th>
      <th>Name</th>
      <th>Subject</th>
      <th>State</th>
      <th>Created</th>
      <th>Duration</th>
      <th>Actions</th>
    </tr>
  </thead>
  <tbody>
    <% @workflows.each do |workflow| %>
      <tr>
        <td><%= link_to workflow.id, workflows_workflow_path(workflow) %></td>
        <td><%= workflow.name %></td>
        <td><%= workflow.subject_type %> #<%= workflow.subject_id %></td>
        <td><span class="badge badge-<%= workflow.state %>"><%= workflow.state %></span></td>
        <td><%= time_ago_in_words(workflow.created_at) %> ago</td>
        <td><%= workflow.duration&.round(2) %>s</td>
        <td>
          <% if workflow.state.in?(%w[running pending]) %>
            <%= button_to "Cancel", cancel_workflows_workflow_path(workflow) %>
          <% end %>
        </td>
      </tr>
    <% end %>
  </tbody>
</table>

<%= paginate @workflows %>
```

```erb
<!-- app/views/workflows/workflows/show.html.erb -->
<h1>Workflow #<%= @workflow.id %></h1>

<div class="workflow-details">
  <p><strong>Name:</strong> <%= @workflow.name %></p>
  <p><strong>State:</strong> <span class="badge badge-<%= @workflow.state %>"><%= @workflow.state %></span></p>
  <p><strong>Subject:</strong> <%= @workflow.subject_type %> #<%= @workflow.subject_id %></p>
  <p><strong>Created:</strong> <%= @workflow.created_at %></p>
  <p><strong>Duration:</strong> <%= @workflow.duration&.round(2) %>s</p>

  <% if @workflow.cancelled? %>
    <p><strong>Cancelled by:</strong> <%= @workflow.cancelled_by %></p>
    <p><strong>Reason:</strong> <%= @workflow.cancellation_reason %></p>
  <% end %>
</div>

<h2>Workflow Graph</h2>
<div class="mermaid">
graph TD
  <% @steps.each do |step| %>
    <%= step.name %>[<%= step.name %>]
    <%= step.name %>:::status_<%= step.status %>
    <% step.depends_on.each do |dep| %>
      <%= dep %> --> <%= step.name %>
    <% end %>
  <% end %>

  classDef status_succeeded fill:#90EE90
  classDef status_failed fill:#FF6B6B
  classDef status_running fill:#4A90E2
  classDef status_pending fill:#E0E0E0
  classDef status_skipped fill:#FFE5B4
  classDef status_cancelled fill:#D3D3D3
</div>

<h2>Steps</h2>
<table>
  <thead>
    <tr>
      <th>Position</th>
      <th>Name</th>
      <th>Status</th>
      <th>Attempts</th>
      <th>Duration</th>
      <th>Output</th>
      <th>Error</th>
    </tr>
  </thead>
  <tbody>
    <% @steps.each do |step| %>
      <tr>
        <td><%= step.position %></td>
        <td><%= step.name %></td>
        <td><span class="badge badge-<%= step.status %>"><%= step.status %></span></td>
        <td><%= step.attempts %> / <%= step.max_attempts %></td>
        <td>
          <% if step.started_at && step.completed_at %>
            <%= (step.completed_at - step.started_at).round(2) %>s
          <% end %>
        </td>
        <td><pre><%= JSON.pretty_generate(step.output) %></pre></td>
        <td>
          <% if step.last_error.present? %>
            <pre><%= step.last_error %></pre>
          <% end %>
          <% if step.skip_reason.present? %>
            <p><strong>Skipped:</strong> <%= step.skip_reason %></p>
          <% end %>
        </td>
      </tr>
    <% end %>
  </tbody>
</table>

<h2>Timeline</h2>
<table>
  <thead>
    <tr>
      <th>Time</th>
      <th>Event</th>
      <th>Step</th>
      <th>Metadata</th>
    </tr>
  </thead>
  <tbody>
    <% @events.each do |event| %>
      <tr>
        <td><%= event.created_at.strftime("%H:%M:%S.%L") %></td>
        <td><%= event.event_type %></td>
        <td><%= event.workflow_step&.name %></td>
        <td><pre><%= JSON.pretty_generate(event.metadata) %></pre></td>
      </tr>
    <% end %>
  </tbody>
</table>

<script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
<script>
  mermaid.initialize({ startOnLoad: true });
</script>
```

### Step 10.4: Add Styling

```css
/* app/assets/stylesheets/workflows.css */
.badge {
  padding: 4px 8px;
  border-radius: 4px;
  font-size: 12px;
  font-weight: bold;
}

.badge-pending {
  background: #e0e0e0;
  color: #333;
}
.badge-running {
  background: #4a90e2;
  color: white;
}
.badge-succeeded {
  background: #90ee90;
  color: #333;
}
.badge-failed {
  background: #ff6b6b;
  color: white;
}
.badge-skipped {
  background: #ffe5b4;
  color: #333;
}
.badge-cancelled {
  background: #d3d3d3;
  color: #333;
}

.mermaid {
  background: white;
  padding: 20px;
  border-radius: 8px;
  margin: 20px 0;
}

pre {
  background: #f5f5f5;
  padding: 10px;
  border-radius: 4px;
  overflow-x: auto;
}

.stats {
  display: flex;
  gap: 20px;
  margin: 20px 0;
}

.stats > div {
  background: #f5f5f5;
  padding: 15px;
  border-radius: 8px;
  flex: 1;
}

table {
  width: 100%;
  border-collapse: collapse;
  margin: 20px 0;
}

th,
td {
  padding: 10px;
  text-align: left;
  border-bottom: 1px solid #ddd;
}

th {
  background: #f5f5f5;
  font-weight: bold;
}
```

---

## Gem Extraction Guide

When ready to extract SolidWorkflow to a gem:

### Step 1: Create Gem Structure

```bash
bundle gem solid_workflow
cd solid_workflow
```

### Step 2: Move Files

```
solid_workflow/
├── lib/
│   ├── solid_workflow/
│   │   ├── version.rb
│   │   ├── engine.rb                    # Rails engine
│   │   ├── workflow.rb                  # Workflow model
│   │   ├── workflow_step.rb             # WorkflowStep model
│   │   ├── workflow_event.rb            # WorkflowEvent model
│   │   ├── application_workflow.rb      # Base workflow class
│   │   ├── workflow_orchestrator.rb     # Orchestrator service
│   │   ├── jobs/
│   │   │   ├── run_workflow_step_job.rb
│   │   │   ├── orchestrate_workflow_job.rb
│   │   │   └── workflow_sweeper_job.rb
│   │   ├── controllers/
│   │   │   └── workflows_controller.rb
│   │   └── views/
│   │       └── workflows/
│   └── solid_workflow.rb                # Main require file
├── db/
│   └── migrate/
│       ├── 001_create_workflows.rb
│       ├── 002_create_workflow_steps.rb
│       └── 003_create_workflow_events.rb
├── spec/
├── README.md
├── solid_workflow.gemspec
└── Gemfile
```

### Step 3: Create Engine

```ruby
# lib/solid_workflow/engine.rb
module SolidWorkflow
  class Engine < ::Rails::Engine
    isolate_namespace SolidWorkflow

    config.generators do |g|
      g.test_framework :rspec
    end

    initializer "solid_workflow.load_migrations" do
      ActiveRecord::Tasks::DatabaseTasks.migrations_paths << File.join(root, "db/migrate")
    end
  end
end
```

### Step 4: Update Gemspec

```ruby
# solid_workflow.gemspec
Gem::Specification.new do |spec|
  spec.name        = "solid_workflow"
  spec.version     = SolidWorkflow::VERSION
  spec.authors     = ["Your Name"]
  spec.email       = ["your@email.com"]

  spec.summary     = "Database-backed workflow orchestration for Rails"
  spec.description = "Build durable, retryable, observable workflows using Solid Queue"
  spec.homepage    = "https://github.com/yourusername/solid_workflow"
  spec.license     = "MIT"

  spec.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]

  spec.add_dependency "rails", ">= 7.0"
  spec.add_dependency "solid_queue", ">= 0.1"
  spec.add_dependency "with_advisory_lock", ">= 4.0"

  spec.add_development_dependency "rspec-rails"
  spec.add_development_dependency "factory_bot_rails"
end
```

### Step 5: Installation Instructions

````ruby
# README.md installation section:

## Installation

Add to Gemfile:
```ruby
gem 'solid_workflow'
````

Install:

```bash
bundle install
rails solid_workflow:install:migrations
rails db:migrate
```

Mount UI (optional):

```ruby
# config/routes.rb
mount SolidWorkflow::Engine, at: "/workflows"
```

### Step 6: Configuration

```ruby
# lib/solid_workflow.rb
module SolidWorkflow
  mattr_accessor :default_retry_config
  @@default_retry_config = { max_attempts: 5, backoff: "exponential" }

  mattr_accessor :sweeper_interval
  @@sweeper_interval = 5.minutes

  def self.configure
    yield self
  end
end

# In host app:
# config/initializers/solid_workflow.rb
SolidWorkflow.configure do |config|
  config.default_retry_config = { max_attempts: 3, backoff: "linear" }
  config.sweeper_interval = 10.minutes
end
```

### Step 7: Publish

```bash
gem build solid_workflow.gemspec
gem push solid_workflow-0.1.0.gem
```

---

## Summary Checklist

- [ ] Phase 1: Database tables created and migrated
- [ ] Phase 2: Core models with associations and validations
- [ ] Phase 3: Basic workflow execution working
- [ ] Phase 4: Parallel execution and dependency resolution
- [ ] Phase 5: Error handling and retry logic
- [ ] Phase 6: Cancellation and skip support
- [ ] Phase 7: Events and metrics for observability
- [ ] Phase 8: Advisory locks and sweeper job
- [ ] Phase 9: Test infrastructure and helpers
- [ ] Phase 10: Web UI (optional)
- [ ] Gem extraction (optional)

Each phase builds on the previous one. Test thoroughly after each phase before proceeding to the next.

---

## Next Steps After Implementation

1. **Monitor in production** - Watch for stuck workflows, high failure rates
2. **Add circuit breakers** - For external API calls (Slack, etc.)
3. **Add step timeouts** - For long-running or hanging steps
4. **Add compensation steps** - For rollback/cleanup logic
5. **Build workflow templates** - Common patterns your team uses
6. **Add webhook triggers** - Start workflows from external events
7. **Add approval steps** - Human-in-the-loop workflows
8. **Build admin tools** - Manual retry, skip, debug tools

---

## Support

For questions or issues during implementation:

1. Review the main SOLID_WORKFLOW.md documentation
2. Check test files for usage examples
3. Use `rails console` to debug workflow state
4. Enable verbose logging in development

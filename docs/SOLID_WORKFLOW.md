# SolidWorkflow

A database-backed workflow orchestration engine for Rails using Solid Queue. Build durable, retryable, observable multi-step workflows without external dependencies.

## Table of Contents

- [Overview](#overview)
- [Core Concepts](#core-concepts)
- [Architecture](#architecture)
- [Installation](#installation)
- [Database Schema](#database-schema)
- [Quick Start](#quick-start)
- [Defining Workflows](#defining-workflows)
- [Step Configuration](#step-configuration)
- [Data Flow](#data-flow)
- [Error Handling](#error-handling)
- [Workflow Control](#workflow-control)
- [Observability](#observability)
- [Testing](#testing)
- [Best Practices](#best-practices)
- [API Reference](#api-reference)

## Overview

SolidWorkflow provides Temporal/AWS Step Functions-like orchestration inside Rails with zero external infrastructure.

**Key Features:**
- ✅ Durable workflow state in Postgres
- ✅ Automatic retries with exponential backoff
- ✅ Parallel step execution (DAG-based)
- ✅ Crash-safe and deploy-safe
- ✅ Step input/output tracking
- ✅ Workflow cancellation and skipping
- ✅ Full observability and audit trail
- ✅ Developer-friendly DSL

**Perfect for:**
- Slack bot multi-step flows
- Incident management workflows
- User onboarding sequences
- Multi-service orchestration
- AI agent tool chains

## Core Concepts

### Workflow

A workflow is a directed acyclic graph (DAG) of steps. Each workflow:
- Has a unique ID and name
- Is attached to a subject (e.g., `Incident`, `User`)
- Contains immutable context (input configuration)
- Has a state: `pending`, `running`, `succeeded`, `failed`, `cancelled`

### Step

A step is a single unit of work. Each step:
- Executes in its own background job
- Can depend on other steps
- Has input (from dependencies) and output (results)
- Is idempotent and retryable
- Has a status: `pending`, `running`, `succeeded`, `failed`, `skipped`, `cancelled`

### Orchestrator

The orchestrator:
- Determines which steps are ready to run
- Schedules Solid Queue jobs for ready steps
- Updates workflow state based on step results
- Uses advisory locks to prevent race conditions

### Execution Model

SolidWorkflow uses a **ping-pong execution model**:

```
Workflow Created
    ↓
Orchestrator → identifies ready steps
    ↓
Step Jobs → execute in parallel
    ↓
Step Complete → calls Orchestrator
    ↓
Orchestrator → identifies next ready steps
    ↓
... repeat until all steps complete
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Workflow Definition                   │
│                   (Ruby Class + DSL)                     │
└─────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────┐
│                  Workflow Instance (DB)                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐             │
│  │  Step A  │  │  Step B  │  │  Step C  │             │
│  │ pending  │→ │ pending  │→ │ pending  │             │
│  └──────────┘  └──────────┘  └──────────┘             │
└─────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────┐
│                     Orchestrator                         │
│           (Advisory Lock + Dependency Check)             │
└─────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────┐
│                   Solid Queue Jobs                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐             │
│  │  Job A   │  │  Job B   │  │  Job C   │             │
│  │ running  │  │ queued   │  │ queued   │             │
│  └──────────┘  └──────────┘  └──────────┘             │
└─────────────────────────────────────────────────────────┘
```

## File Organization

SolidWorkflow follows 37signals/Rails conventions with a concern-based architecture:

```
app/
├── models/
│   ├── workflow.rb                   # Main workflow model
│   ├── workflow/                     # Workflow-specific concerns
│   │   ├── stateable.rb             # State machine logic
│   │   ├── eventable.rb             # Event tracking
│   │   ├── orchestratable.rb        # Orchestration logic
│   │   ├── cancellable.rb           # Cancellation logic
│   │   └── metrics.rb               # Metrics and analytics
│   ├── workflow_step.rb             # Main step model
│   ├── workflow_step/               # Step-specific concerns
│   │   ├── statusable.rb            # Status enum and scopes
│   │   ├── executable.rb            # Execution logic
│   │   ├── retryable.rb             # Retry logic
│   │   ├── dependencies.rb          # Dependency resolution
│   │   └── metrics.rb               # Step metrics
│   ├── workflow_event.rb            # Event model
│   └── concerns/
│       └── workflow_events.rb       # Event type constants
├── workflows/
│   ├── base.rb                      # Workflows::Base (base class)
│   ├── incident_creation.rb         # IncidentCreation workflow
│   └── welcome_user.rb              # WelcomeUser workflow
├── jobs/
│   └── workflows/                   # Namespaced jobs
│       ├── run_step_job.rb         # Workflows::RunStepJob
│       ├── orchestrate_job.rb      # Workflows::OrchestrateJob
│       └── workflow_sweeper_job.rb # WorkflowSweeperJob
└── controllers/
    └── workflows_controller.rb      # WorkflowsController
```

**Key Principles:**
- **No service objects** - Use model concerns instead
- **Thin jobs** - Jobs delegate to model methods
- **`_later`/`_now` suffix** - `execute_later` enqueues job, `execute_now` runs synchronously
- **Concerns over inheritance** - Break features into focused concerns
- **Resource-oriented controllers** - Use nested resources for actions

## Installation

### 1. Install Dependencies

```ruby
# Gemfile
gem "solid_queue"
gem "solid_cache"
```

### 2. Run Migrations

See [Database Schema](#database-schema) section for migration files.

### 3. Configure Solid Queue

```ruby
# config/queue.yml
production:
  dispatchers:
    - polling_interval: 1
      batch_size: 500
  workers:
    - queues: workflows
      threads: 5
      processes: 3
```

## Database Schema

### Workflows Table

```ruby
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

  t.index [:subject_type, :subject_id]
  t.index :state
  t.index :workflow_class
  t.index :created_at
end
```

### Workflow Steps Table

```ruby
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

  t.index :workflow_id
  t.index [:workflow_id, :name]
  t.index [:workflow_id, :status]
  t.index :status
  t.index :run_at
end

add_foreign_key :workflow_steps, :workflows
```

### Workflow Events Table

```ruby
create_table :workflow_events, id: :uuid do |t|
  t.uuid       :workflow_id,      null: false
  t.uuid       :workflow_step_id
  t.string     :event_type,       null: false
  t.jsonb      :metadata,         default: {}
  t.timestamp  :created_at,       null: false

  t.index :workflow_id
  t.index :workflow_step_id
  t.index [:workflow_id, :created_at]
  t.index :event_type
  t.index :created_at
end

add_foreign_key :workflow_events, :workflows
add_foreign_key :workflow_events, :workflow_steps
```

## Quick Start

### 1. Define a Workflow

```ruby
class WelcomeUser < Workflows::Base
  workflow_name "user.welcome.v1"

  step :create_user_record
  step :send_welcome_email,    depends_on: [:create_user_record]
  step :create_slack_channel,  depends_on: [:create_user_record]
  step :invite_to_slack,       depends_on: [:create_slack_channel]

  def create_user_record(workflow:, step:, input:)
    user = workflow.subject
    user.update!(status: "active")
    { user_id: user.id }
  end

  def send_welcome_email(workflow:, step:, input:)
    user = workflow.subject
    UserMailer.welcome_email(user).deliver_later
    { email_sent_at: Time.current }
  end

  def create_slack_channel(workflow:, step:, input:)
    user = workflow.subject
    channel_id = SlackClient.create_channel("welcome-#{user.id}")
    { channel_id: channel_id }
  end

  def invite_to_slack(workflow:, step:, input:)
    user = workflow.subject
    channel_id = input.dig("create_slack_channel", "channel_id")

    SlackClient.invite_user(user.slack_id, channel_id)
    { invited_at: Time.current }
  end
end
```

### 2. Start a Workflow

```ruby
user = User.find(123)

# Async mode (default) - steps execute in background jobs
workflow = WelcomeUser.start!(
  user,
  context: {
    source: "admin_panel",
    admin_id: current_user.id
  }
)
# => #<Workflow id: 456, state: "pending", ...>

# Sync mode - useful for console debugging or tests
workflow = WelcomeUser.start_inline!(user, context: { source: "console" })
# => #<Workflow id: 457, state: "succeeded", ...>
```

### 3. Monitor Progress

```ruby
workflow.reload.state
# => "running"

workflow.workflow_steps.pluck(:name, :status)
# => [
#   ["create_user_record", "succeeded"],
#   ["send_welcome_email", "running"],
#   ["create_slack_channel", "succeeded"],
#   ["invite_to_slack", "pending"]
# ]
```

## Defining Workflows

### Basic Structure

```ruby
class MyWorkflow < Workflows::Base
  # Workflow metadata
  workflow_name "my_workflow.v1"

  workflow_config(
    max_concurrent_steps: 5,
    timeout: 1.hour
  )

  # Define steps
  step :step_one
  step :step_two, depends_on: [:step_one]
  step :step_three, depends_on: [:step_one, :step_two]

  # Implement step methods
  def step_one(workflow:, step:, input:)
    # Your logic here
    { result: "value" }
  end

  def step_two(workflow:, step:, input:)
    # Access previous step output
    value = input.dig("step_one", "result")

    { another_result: "another_value" }
  end
end
```

### Step Methods

Each step method receives:
- `workflow` - The workflow instance (access `.subject`, `.context`)
- `step` - The step instance (access `.name`, `.attempts`, `.input`)
- `input` - Hash of dependency outputs (auto-injected by orchestrator)

Each step method must return:
- A hash (stored in `step.output`)
- Or `nil` (empty hash is stored)

### Accessing Workflow Data

```ruby
def my_step(workflow:, step:, input:)
  # Access subject
  incident = workflow.subject

  # Access immutable context
  slack_team_id = workflow.context["slack_team_id"]

  # Access previous step output
  channel_id = input.dig("create_channel", "channel_id")

  # Access current step info
  attempt_number = step.attempts

  # Return output
  {
    message_id: "123",
    posted_at: Time.current
  }
end
```

## Step Configuration

### Dependencies

```ruby
# No dependencies - runs immediately
step :step_a

# Single dependency
step :step_b, depends_on: [:step_a]

# Multiple dependencies (waits for ALL)
step :step_c, depends_on: [:step_a, :step_b]

# Parallel execution
step :step_d, depends_on: [:step_a]  # Runs in parallel with step_b
step :step_e, depends_on: [:step_a]  # Runs in parallel with step_b, step_d
```

### Retry Configuration

```ruby
# Default retry (5 attempts, exponential backoff)
step :my_step

# Custom retry
step :my_step,
     retry_config: {
       max_attempts: 3,
       backoff: WorkflowStep::Retryable::BACKOFF_EXPONENTIAL  # or BACKOFF_LINEAR, BACKOFF_FIXED
     }

# No retries
step :my_step,
     retry_config: {
       max_attempts: 1
     }

# Custom backoff
step :my_step,
     retry_config: {
       max_attempts: 5,
       backoff: WorkflowStep::Retryable::BACKOFF_FIXED,
       backoff_seconds: 30
     }
```

### Conditional Steps (Skip Logic)

```ruby
def send_premium_feature_notification(workflow:, step:, input:)
  team = workflow.subject.team

  unless team.premium?
    step.update!(
      status: "skipped",
      skip_reason: "Team is not on premium plan"
    )
    return { skipped: true }
  end

  # Actual logic
  send_notification(team)
  { sent: true }
end
```

### Workflow Configuration

```ruby
workflow_config(
  max_concurrent_steps: 3,  # Limit parallel execution
  timeout: 30.minutes       # Workflow-level timeout
)
```

## Data Flow

### Context (Immutable Input)

Context is set at workflow creation and never changes. Use for configuration.

```ruby
workflow = MyWorkflow.start!(
  incident,
  context: {
    slack_team_id: "T123",
    severity: "high",
    requested_by: "user@example.com"
  }
)

# In any step:
def my_step(workflow:, step:, input:)
  team_id = workflow.context["slack_team_id"]  # Always available
end
```

**Never modify context:**
```ruby
# ❌ DON'T DO THIS
workflow.context["new_key"] = "value"
workflow.save!
```

### Step Output (Mutable Results)

Step output is the return value of each step method.

```ruby
def create_channel(workflow:, step:, input:)
  channel_id = SlackClient.create_channel("incident-123")

  # This hash is stored in step.output
  { channel_id: channel_id }
end
```

### Step Input (Auto-Injected Dependencies)

The orchestrator automatically populates `input` with outputs from dependency steps.

```ruby
step :create_channel
step :post_message, depends_on: [:create_channel]
step :invite_users, depends_on: [:create_channel]

def create_channel(workflow:, step:, input:)
  { channel_id: "C123" }
end

def post_message(workflow:, step:, input:)
  # Orchestrator auto-injects create_channel output
  channel_id = input.dig("create_channel", "channel_id")
  # => "C123"

  SlackClient.post_message(channel_id, "Hello!")
end

def invite_users(workflow:, step:, input:)
  # Same input available here
  channel_id = input.dig("create_channel", "channel_id")
  # => "C123"
end
```

## Error Handling

### Automatic Retries

Steps automatically retry on failure with exponential backoff:

```ruby
# Default retry behavior:
# Attempt 1: immediate
# Attempt 2: wait 2 seconds
# Attempt 3: wait 4 seconds
# Attempt 4: wait 8 seconds
# Attempt 5: wait 16 seconds
# After 5 attempts: step fails, workflow fails
```

### Idempotency Pattern

Always make steps idempotent to handle retries safely:

```ruby
def create_slack_channel(workflow:, step:, input:)
  incident = workflow.subject

  # Check if already created (idempotency)
  return { channel_id: incident.slack_channel_id } if incident.slack_channel_id

  # Check if exists in Slack
  name = "inc-#{incident.id}"
  existing = SlackClient.find_channel_by_name(name)
  if existing
    incident.update!(slack_channel_id: existing)
    return { channel_id: existing }
  end

  # Create new
  channel_id = SlackClient.create_channel(name)
  incident.update!(slack_channel_id: channel_id)

  { channel_id: channel_id }
end
```

### Error Information

```ruby
step = workflow.workflow_steps.find_by(status: "failed")

step.last_error
# => "Slack::Web::Api::Errors::SlackError: channel_not_found"

step.attempts
# => 5
```

### Workflow Failure

A workflow fails when any step exhausts its retry attempts:

```ruby
workflow.state
# => "failed"

workflow.workflow_steps.where(status: "failed")
# => [#<WorkflowStep name: "create_channel", attempts: 5, ...>]
```

## Workflow Control

### Cancellation

```ruby
workflow = MyWorkflow.start!(subject)

# Cancel workflow
workflow.cancel!(
  reason: "User requested cancellation",
  by: "admin@example.com"
)

workflow.state
# => "cancelled"

workflow.workflow_steps.where(status: "pending").count
# => 0 (all cancelled)

workflow.workflow_steps.where(status: "running").count
# => 1 (running steps complete but don't trigger new steps)
```

### Pause/Resume (Future)

Temporarily stop a workflow, then continue it later.

**Use cases:**
- Wait for external approval (e.g., "Pause until manager approves budget")
- Scheduled maintenance (e.g., "Pause all workflows during deployment")
- Rate limiting (e.g., "Pause workflows hitting Slack API limits")
- Human intervention (e.g., "Pause until user provides more info")

```ruby
# Not yet implemented
workflow = IncidentCreation.start!(incident)
# Workflow is running...

workflow.pause!  # Stop scheduling new steps
# state: "paused", running steps complete but no new steps start

# Later...
workflow.resume!  # Continue where it left off
# Orchestrator runs, schedules next ready steps
```

### Manual Step Retry/Skip (Future)

Admin can manually retry failed steps or skip problematic ones.

**Retry - Use cases:**
- Transient failures now resolved (API back up, credentials fixed)
- External service was down temporarily
- Network issue has been resolved

**Skip - Use cases:**
- Non-critical step failing, want to complete workflow anyway
- Step is optional and can be safely omitted
- Workaround applied manually outside workflow

```ruby
# Not yet implemented

# Retry a failed step
step = workflow.workflow_steps.find_by(name: "create_channel", status: "failed")
step.retry_now!
# Resets: status → "pending", attempts → 0, last_error → nil
# Triggers: orchestrator to schedule it immediately

# Skip a problematic step
step = workflow.workflow_steps.find_by(name: "post_announcement", status: "failed")
step.skip!(reason: "Channel archived, not critical")
# Sets: status → "skipped", skip_reason → "..."
# Triggers: orchestrator to continue with dependent steps
```

## Observability

### Workflow Events

Every significant action is logged:

```ruby
workflow.workflow_events.pluck(:event_type, :created_at)
# => [
#   ["workflow.started", 2025-01-01 10:00:00],
#   ["step.started", 2025-01-01 10:00:01],
#   ["step.succeeded", 2025-01-01 10:00:05],
#   ["workflow.succeeded", 2025-01-01 10:01:00]
# ]

# Filter by event type
workflow.workflow_events.where(event_type: "step.failed")

# View metadata
event = workflow.workflow_events.last
event.metadata
# => { "step_name" => "create_channel", "error" => "..." }
```

### Event Types

- `workflow.started`
- `workflow.succeeded`
- `workflow.failed`
- `workflow.cancelled`
- `step.started`
- `step.succeeded`
- `step.failed`
- `step.skipped`
- `step.cancelled`

### Metrics

Track key metrics for monitoring using built-in metrics concerns:

```ruby
# Workflow summary statistics
Workflow.summary
# => {
#   total: 45,
#   by_state: { "succeeded" => 40, "running" => 3, "failed" => 2 },
#   by_workflow_class: { "IncidentCreation" => 30, "UserOnboarding" => 15 },
#   avg_duration: 125.5,
#   stuck_count: 1
# }

# Average workflow duration
Workflow.average_duration(time_range: 24.hours.ago..)
# => 125.5 (seconds)

# Failure rate
Workflow.failure_rate(time_range: 7.days.ago..)
# => 4.5 (percent)

Workflow.failure_rate(workflow_class: "IncidentCreation")
# => 2.1 (percent)

# State summary
Workflow.state_summary(time_range: 1.hour.ago..)
# => { "succeeded" => 45, "running" => 3, "failed" => 2 }

# Step statistics
WorkflowStep.step_stats
# => {
#   ["create_channel", "succeeded"] => 45,
#   ["create_channel", "failed"] => 2,
#   ["post_message", "succeeded"] => 43
# }

# Step failure rates
WorkflowStep.step_failure_rates
# => {
#   "create_channel" => 4.5,
#   "post_message" => 2.1
# }

# Average step durations
WorkflowStep.average_step_durations
# => {
#   "create_channel" => 2.5,
#   "post_message" => 1.2
# }

# Instance methods
workflow.duration
# => 125.5

workflow.stuck?
# => false

step.duration
# => 2.5
```

### Querying Workflows

```ruby
# Using scopes
Workflow.active
# => All pending or running workflows

Workflow.completed
# => All succeeded, failed, or cancelled workflows

Workflow.stuck
# => Active workflows that haven't updated in 5+ minutes

Workflow.stuck(10.minutes.ago)
# => Stuck workflows with custom threshold

# All running workflows
Workflow.running

# Workflows for a subject
incident.workflows

# Failed workflows in last 24h
Workflow.failed.where(created_at: 24.hours.ago..)

# Workflows with specific step failed
Workflow.joins(:workflow_steps)
  .where(workflow_steps: { name: "create_channel", status: "failed" })

# Orphaned steps
WorkflowStep.orphaned
# => Steps stuck in "running" for 10+ minutes

WorkflowStep.orphaned(15.minutes.ago)
# => Orphaned steps with custom threshold
```

## Testing

### Synchronous Test Mode

SolidWorkflow includes built-in support for synchronous testing. Use the `run_workflow_sync` helper to execute workflows without background jobs:

```ruby
# spec/support/workflow_helpers.rb is auto-loaded
RSpec.describe WelcomeUserWorkflow, type: :workflow do
  let(:user) { create(:user) }

  it "executes all steps in order" do
    workflow = run_workflow_sync(WelcomeUserWorkflow, user)

    expect_workflow_succeeded(workflow)
  end

  it "passes data between steps" do
    workflow = run_workflow_sync(WelcomeUserWorkflow, user)

    step = find_step(workflow, :send_welcome_email)
    expect(step.succeeded?).to be true
  end
end
```

### Test Helpers

The `WorkflowHelpers` module provides convenient test helpers:

```ruby
# Run workflow synchronously
workflow = run_workflow_sync(MyWorkflow, user, context: { source: "admin" })

# Assertions
expect_workflow_succeeded(workflow)
expect_workflow_failed(workflow)

# Find and inspect steps
step = find_step(workflow, :create_channel)
expect(step.output["channel_id"]).to eq("C123")

# Check step output
expect_step_output(workflow, :create_channel, channel_id: "C123")

# Check skipped steps
expect_step_skipped(workflow, :premium_feature, reason: "User not premium")

# Debug helper
step_statuses(workflow)
# => { "step_one" => "succeeded", "step_two" => "succeeded" }
```

### How It Works

SolidWorkflow provides two methods for starting workflows:

```ruby
# Asynchronous (default) - steps execute in background jobs
workflow = MyWorkflow.start!(subject, context: { ... })

# Synchronous - executes entire workflow immediately
workflow = MyWorkflow.start_inline!(subject, context: { ... })
```

The `run_workflow_sync` helper simply calls `start_inline!` for you.

### Test Example

```ruby
RSpec.describe WelcomeUserWorkflow, type: :workflow do
  let(:user) { create(:user) }

  before do
    # Mock external services
    allow(SlackClient).to receive(:create_channel).and_return("C123")
    allow(SlackClient).to receive(:invite_user).and_return(true)
  end

  it "creates user and sends welcome email" do
    workflow = run_workflow_sync(WelcomeUserWorkflow, user, context: { source: "test" })

    expect_workflow_succeeded(workflow)
    expect_step_output(workflow, :create_slack_channel, channel_id: "C123")
  end

  it "handles Slack API failures with retry" do
    call_count = 0
    allow(SlackClient).to receive(:create_channel) do
      call_count += 1
      raise Slack::Web::Api::Errors::SlackError, "rate_limited" if call_count < 3
      "C123"
    end

    workflow = run_workflow_sync(WelcomeUserWorkflow, user)

    expect_workflow_succeeded(workflow)
    expect(call_count).to eq(3)  # Failed twice, succeeded third time

    # Verify retry tracking
    step = find_step(workflow, :create_slack_channel)
    expect(step.attempts).to eq(3)
  end

  it "skips premium step for non-premium users" do
    user = create(:user, premium: false)

    workflow = run_workflow_sync(PremiumOnboardingWorkflow, user)

    expect_workflow_succeeded(workflow)
    expect_step_skipped(workflow, :send_premium_welcome, reason: "not on premium plan")
  end

  it "is idempotent when retried" do
    user.update!(slack_channel_id: "C123", initial_message_ts: "123.456")

    # Should not call external APIs
    expect(SlackClient).not_to receive(:create_channel)
    expect(SlackClient).not_to receive(:post_message)

    workflow = run_workflow_sync(WelcomeUserWorkflow, user)
    expect_workflow_succeeded(workflow)
  end
end
```

### Testing Individual Steps

```ruby
RSpec.describe WelcomeUserWorkflow do
  describe "#create_slack_channel" do
    it "creates channel and returns channel_id" do
      user = create(:user)
      workflow = create(:workflow, subject: user, context: {})
      step = create(:workflow_step, workflow: workflow, name: "create_slack_channel")

      allow(SlackClient).to receive(:create_channel).and_return("C123")

      instance = WelcomeUserWorkflow.new
      result = instance.create_slack_channel(workflow: workflow, step: step, input: {})

      expect(result[:channel_id]).to eq("C123")
    end

    it "is idempotent on retry" do
      user = create(:user, slack_channel_id: "C123")
      workflow = create(:workflow, subject: user)
      step = create(:workflow_step, workflow: workflow, name: "create_slack_channel")

      # Should not call API
      expect(SlackClient).not_to receive(:create_channel)

      instance = WelcomeUserWorkflow.new
      result = instance.create_slack_channel(workflow: workflow, step: step, input: {})

      expect(result[:channel_id]).to eq("C123")
    end
  end
end
```

## Optional Features

SolidWorkflow includes optional features for enhanced functionality and developer experience.

### Idempotency Helpers

The `IdempotentSteps` module provides reusable patterns for making steps safe to retry:

```ruby
class MyWorkflow < Workflows::Base
  # IdempotentSteps is automatically included

  def create_channel(workflow:, step:, input:)
    incident = workflow.subject

    # Helper automatically checks if field exists
    idempotent_field(incident, :slack_channel_id) do
      SlackClient.create_channel("inc-#{incident.id}")
    end
  end
end
```

**Available helpers:**

```ruby
# Check field, return value or execute block
idempotent_field(record, :field_name) do
  # Create/fetch value
end

# Find existing or create
find_or_create(
  local_check: -> { incident.slack_channel_id },
  external_check: -> { SlackClient.find_channel("inc-#{incident.id}") },
  create: -> { SlackClient.create_channel("inc-#{incident.id}") }
)

# Conditional execution with skip
conditional_step(user.premium?, skip_reason: "User not premium") do
  PremiumMailer.welcome(user).deliver_now
  { email_sent: true }
end

# Retry with backoff for transient errors
with_retry(max_attempts: 3, rescue_classes: [Slack::Web::Api::Errors::TooManyRequestsError]) do
  SlackClient.post_message(channel, text)
end
```

### Pause and Resume

Workflows can be paused and resumed for human approvals or rate limiting:

```ruby
# Pause workflow
workflow.pause!(
  reason: "Waiting for manager approval",
  by: "approval_system"
)

# Resume later
workflow.resume!(by: "manager@example.com")

# Check if paused
workflow.paused? # => true

# Get pause metadata
workflow.pause_metadata
# => {
#   paused_at: 2025-01-15 10:30:00,
#   paused_by: "approval_system",
#   pause_reason: "Waiting for manager approval",
#   resumed_at: 2025-01-15 11:00:00,
#   resumed_by: "manager@example.com"
# }

# Calculate pause duration
workflow.paused_duration # => 1800.0 (seconds)
```

**Use cases:**

```ruby
# Wait for approval
def wait_for_approval(workflow:, step:, input:)
  ManagerMailer.approval_request(workflow).deliver_later
  workflow.pause!(reason: "Awaiting manager approval")
  { paused: true }
end

# Later, when manager approves
workflow.resume!(by: current_user.email)
# Workflow continues automatically

# Automatic resume after delay
def handle_rate_limit(workflow:, step:, input:)
  workflow.pause!(reason: "Slack rate limit hit")
  ResumeWorkflowJob.set(wait: 60.seconds).perform_later(workflow.id)
end
```

### Structured Logging

All workflow operations are logged with structured data:

```ruby
# Step start
# [INFO] workflow_step_started workflow_id=abc-123 step_name=create_channel attempt=1

# Step success
# [INFO] workflow_step_succeeded workflow_id=abc-123 step_name=create_channel duration_seconds=2.5

# Step failure
# [ERROR] workflow_step_failed workflow_id=abc-123 step_name=post_message error_class=Slack::Web::Api::Errors::TooManyRequestsError will_retry=true

# Orchestration
# [INFO] workflow_orchestration_started workflow_id=abc-123 current_state=running
# [INFO] workflow_orchestration_completed workflow_id=abc-123 new_state=running duration_seconds=0.05
```

Log fields include:
- `workflow_id`, `workflow_class`
- `step_id`, `step_name`
- `attempt`, `max_attempts`, `will_retry`
- `duration_seconds`
- `error_class`, `error_message`, `backtrace`
- `subject_type`, `subject_id`

### Workflow Validations

Models include validations to catch configuration errors:

```ruby
# Validates workflow_class exists and inherits from Workflows::Base
Workflow.create!(
  workflow_class: "NonExistentWorkflow", # ❌
  subject: incident
)
# => ActiveRecord::RecordInvalid: workflow_class must be a valid class name

Workflow.create!(
  workflow_class: "SomeRandomClass", # ❌ Not a Workflows::Base subclass
  subject: incident
)
# => ActiveRecord::RecordInvalid: workflow_class must inherit from Workflows::Base
```

## Best Practices

### 1. Make Steps Idempotent

Always check if work was already done:

```ruby
def create_resource(workflow:, step:, input:)
  subject = workflow.subject

  # Check DB first
  return { resource_id: subject.resource_id } if subject.resource_id

  # Check external system
  existing = ExternalService.find_by_name("resource-#{subject.id}")
  if existing
    subject.update!(resource_id: existing.id)
    return { resource_id: existing.id }
  end

  # Create new
  resource = ExternalService.create(name: "resource-#{subject.id}")
  subject.update!(resource_id: resource.id)

  { resource_id: resource.id }
end
```

### 2. Use Context for Configuration Only

```ruby
# ✅ Good - immutable config
workflow = MyWorkflow.start!(
  incident,
  context: {
    slack_team_id: "T123",
    severity: "high",
    notification_channels: ["#incidents", "#on-call"]
  }
)

# ❌ Bad - trying to pass mutable data
workflow = MyWorkflow.start!(
  incident,
  context: {
    channel_id: nil  # Will be set by step
  }
)
```

### 3. Use Step Output for Results

```ruby
# ✅ Good - use step output
def create_channel(workflow:, step:, input:)
  channel_id = create_slack_channel(...)
  { channel_id: channel_id }  # Next steps get this via input
end

def post_message(workflow:, step:, input:)
  channel_id = input.dig("create_channel", "channel_id")
  # ...
end
```

### 4. Name Steps Descriptively

```ruby
# ✅ Good
step :create_slack_incident_channel
step :post_incident_details_message
step :invite_on_call_responders

# ❌ Bad
step :step1
step :do_thing
step :process
```

### 5. Keep Steps Small and Focused

```ruby
# ✅ Good - single responsibility
step :create_channel
step :post_message
step :invite_users

# ❌ Bad - too much in one step
step :setup_slack  # Creates channel, posts message, invites users
```

### 6. Handle Errors Gracefully

```ruby
def external_api_call(workflow:, step:, input:)
  begin
    result = ExternalAPI.call(...)
    { success: true, data: result }
  rescue ExternalAPI::RateLimitError => e
    # Log and let retry handle it
    Rails.logger.warn("Rate limited, will retry: #{e}")
    raise
  rescue ExternalAPI::NotFoundError => e
    # Some errors shouldn't retry
    step.update!(
      status: "failed",
      last_error: "Resource not found: #{e}"
    )
    { success: false, error: e.message }
  end
end
```

### 7. Version Your Workflows

When making breaking changes, create a new workflow class:

```ruby
class IncidentCreationV1 < Workflows::Base
  workflow_name "incident.create.v1"
  # ...
end

class IncidentCreationV2 < Workflows::Base
  workflow_name "incident.create.v2"
  # New/changed steps
end

# In application code, use latest
class IncidentCreation < IncidentCreationV2
end
```

### 8. Add Skip Reasons

Always explain why a step was skipped:

```ruby
unless condition
  step.update!(
    status: "skipped",
    skip_reason: "Specific reason here"  # ← Always include
  )
  return { skipped: true }
end
```

### 9. Use Workflow Config for Rate Limiting

```ruby
class SlackIntensive < Workflows::Base
  workflow_config(
    max_concurrent_steps: 2  # Limit Slack API calls
  )

  # 10 steps that call Slack API
  # Only 2 will run at once
end
```

### 10. Monitor and Alert

Set up monitoring for:
- Stuck workflows (running > 30 min)
- High failure rates
- Specific step failures
- Workflow duration spikes

```ruby
# Example alerting
if Workflow.where(state: "running").where("updated_at < ?", 30.minutes.ago).exists?
  alert("Stuck workflows detected!")
end
```

## API Reference

### Workflows::Base

**Class Methods:**

- `workflow_name(name)` - Set workflow name
- `workflow_config(config)` - Set workflow configuration
- `step(name, depends_on: [], retry_config: {})` - Define a step
- `steps` - Get array of step definitions
- `start!(subject, context: {})` - Create and start a workflow

**Instance Methods:**

- `run_step(step_name, workflow:, step:)` - Execute a step (called by job)

### Workflow Model

**Attributes:**

- `name` - Workflow name
- `workflow_class` - Class name
- `subject` - Polymorphic association
- `state` - Current state
- `context` - Immutable input (JSONB)
- `workflow_config` - Configuration (JSONB)
- `started_at`, `completed_at` - Timestamps
- `cancelled_by`, `cancellation_reason` - Cancellation info

**Associations:**

- `workflow_steps` - Has many steps
- `workflow_events` - Has many events

**Methods:**

- `cancel!(reason:, by:)` - Cancel workflow
- `record_event(type, **metadata)` - Log an event

**Scopes:**

- `Workflow.running` - Currently running
- `Workflow.pending` - Not started
- `Workflow.completed` - Succeeded/failed/cancelled

### WorkflowStep Model

**Attributes:**

- `name` - Step name
- `status` - Current status
- `depends_on` - Array of dependency names
- `position` - Order in workflow
- `attempts` - Retry count
- `max_attempts` - Max retries
- `run_at` - Scheduled time (for retries)
- `started_at`, `completed_at` - Timestamps
- `input` - Input from dependencies (JSONB)
- `output` - Step results (JSONB)
- `retry_config` - Retry configuration (JSONB)
- `last_error` - Error message
- `skip_reason` - Why step was skipped

**Associations:**

- `workflow` - Belongs to workflow
- `workflow_events` - Has many events

**Methods:**

- `ready_to_run?(all_steps)` - Check if step can execute

### WorkflowEvent Model

**Attributes:**

- `event_type` - Type of event
- `metadata` - Additional data (JSONB)
- `created_at` - When event occurred

**Associations:**

- `workflow` - Belongs to workflow
- `workflow_step` - Optionally belongs to step

### Workflow::Orchestratable Concern

**Instance Methods:**

- `enqueue_next_steps` - Schedule ready steps (with advisory lock)
- `enqueue_next_steps_later` - Schedule orchestration with debounce

**Private Methods:**

- `apply_concurrency_limit(all_steps, ready_steps)` - Limit concurrent steps
- `update_workflow_state(steps)` - Update workflow state based on step statuses

### Jobs

**Workflows::RunStepJob:**
- `perform(step_id)` - Execute a step

**Workflows::OrchestrateJob:**
- `perform(workflow_id)` - Run orchestration for workflow (debounced)

**WorkflowSweeperJob:**
- `perform` - Resume stuck workflows (run periodically)

---

## Future Enhancements

- [ ] Web UI for workflow visualization
- [ ] Pause/resume workflows
- [ ] Manual step retry/skip
- [ ] Workflow templates
- [ ] Step-level timeouts
- [ ] Compensation/rollback steps
- [ ] Human approval steps
- [ ] Webhook triggers
- [ ] Scheduled workflows
- [ ] Workflow branching (conditional paths)

---

## License

MIT License (when extracted to gem)

## Contributing

1. Fork the repository
2. Create your feature branch
3. Write tests
4. Submit a pull request

## Support

- GitHub Issues: [link when gem released]
- Documentation: [link when gem released]

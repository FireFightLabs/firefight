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
create_table :workflows do |t|
  t.string   :name,                null: false
  t.string   :workflow_class,      null: false
  t.string   :subject_type,        null: false
  t.bigint   :subject_id,          null: false
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
create_table :workflow_steps do |t|
  t.references :workflow,      null: false, foreign_key: true
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

  t.index [:workflow_id, :name]
  t.index [:workflow_id, :status]
  t.index :status
  t.index :run_at
end
```

### Workflow Events Table

```ruby
create_table :workflow_events do |t|
  t.references :workflow,      null: false, foreign_key: true
  t.references :workflow_step, foreign_key: true
  t.string     :event_type,    null: false
  t.jsonb      :metadata,      default: {}
  t.timestamp  :created_at,    null: false

  t.index [:workflow_id, :created_at]
  t.index :event_type
  t.index :created_at
end
```

## Quick Start

### 1. Define a Workflow

```ruby
class WelcomeUserWorkflow < ApplicationWorkflow
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

workflow = WelcomeUserWorkflow.start!(
  user,
  context: {
    source: "admin_panel",
    admin_id: current_user.id
  }
)

# => #<Workflow id: 456, state: "pending", ...>
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
class MyWorkflow < ApplicationWorkflow
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
       backoff: "exponential"  # or "linear", "fixed"
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
       backoff: "fixed",
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

```ruby
# Not yet implemented
workflow.pause!
workflow.resume!
```

### Manual Step Retry (Future)

```ruby
# Not yet implemented
step = workflow.workflow_steps.find_by(name: "create_channel")
step.retry_now!
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

Track key metrics for monitoring:

```ruby
# Query workflow stats
Workflow.where(created_at: 1.hour.ago..).group(:state).count
# => { "succeeded" => 45, "running" => 3, "failed" => 2 }

# Average workflow duration
Workflow.where(state: "succeeded")
  .where("completed_at > ?", 24.hours.ago)
  .average("EXTRACT(EPOCH FROM (completed_at - created_at))")
# => 125.5 (seconds)

# Step failure rate
WorkflowStep.where(created_at: 1.day.ago..)
  .group(:name, :status).count
```

### Querying Workflows

```ruby
# All running workflows
Workflow.where(state: "running")

# Workflows for a subject
incident.workflows

# Failed workflows in last 24h
Workflow.where(state: "failed")
  .where("created_at > ?", 24.hours.ago)

# Workflows with specific step failed
Workflow.joins(:workflow_steps)
  .where(workflow_steps: { name: "create_channel", status: "failed" })

# Stuck workflows (updated more than 30min ago)
Workflow.where(state: "running")
  .where("updated_at < ?", 30.minutes.ago)
```

## Testing

### Synchronous Test Mode

Run workflows synchronously in tests:

```ruby
# In test environment
class ApplicationWorkflow
  def self.start!(subject, context: {})
    if Rails.env.test?
      start_inline!(subject, context: context)
    else
      start_async!(subject, context: context)
    end
  end

  def self.start_inline!(subject, context: {})
    wf = create_workflow!(subject, context)

    # Execute synchronously
    loop do
      wf.reload
      steps = wf.workflow_steps.reload.to_a

      ready = steps.select { |s| WorkflowOrchestrator.ready_to_run?(s, steps) }
      break if ready.empty?

      ready.each do |step|
        RunWorkflowStepJob.new.perform(step.id)
      end

      WorkflowOrchestrator.enqueue_next_steps!(wf)
    end

    wf.reload
  end
end
```

### Test Example

```ruby
RSpec.describe WelcomeUserWorkflow do
  it "creates user and sends welcome email" do
    user = create(:user)

    # Mock external services
    allow(SlackClient).to receive(:create_channel).and_return("C123")
    allow(SlackClient).to receive(:invite_user).and_return(true)

    workflow = WelcomeUserWorkflow.start!(
      user,
      context: { source: "test" }
    )

    expect(workflow.state).to eq("succeeded")
    expect(workflow.workflow_steps.pluck(:status).uniq).to eq(["succeeded"])

    # Verify step outputs
    channel_step = workflow.workflow_steps.find_by(name: "create_slack_channel")
    expect(channel_step.output["channel_id"]).to eq("C123")
  end

  it "handles Slack API failures with retry" do
    user = create(:user)

    call_count = 0
    allow(SlackClient).to receive(:create_channel) do
      call_count += 1
      raise Slack::Web::Api::Errors::SlackError, "rate_limited" if call_count < 3
      "C123"
    end

    workflow = WelcomeUserWorkflow.start!(user)

    expect(workflow.state).to eq("succeeded")
    expect(call_count).to eq(3)  # Failed twice, succeeded third time
  end

  it "skips premium step for non-premium users" do
    user = create(:user, premium: false)

    workflow = PremiumOnboardingWorkflow.start!(user)

    skip_step = workflow.workflow_steps.find_by(name: "send_premium_welcome")
    expect(skip_step.status).to eq("skipped")
    expect(skip_step.skip_reason).to eq("User is not on premium plan")
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
class IncidentCreationWorkflowV1 < ApplicationWorkflow
  workflow_name "incident.create.v1"
  # ...
end

class IncidentCreationWorkflowV2 < ApplicationWorkflow
  workflow_name "incident.create.v2"
  # New/changed steps
end

# In application code, use latest
class IncidentCreationWorkflow < IncidentCreationWorkflowV2
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
class SlackIntensiveWorkflow < ApplicationWorkflow
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

### ApplicationWorkflow

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

### WorkflowOrchestrator

**Class Methods:**

- `enqueue_next_steps!(workflow)` - Schedule ready steps
- `ready_to_run?(step, all_steps)` - Check if step is ready

### Jobs

**RunWorkflowStepJob:**
- `perform(step_id)` - Execute a step

**OrchestrateWorkflowJob:**
- `perform(workflow_id)` - Run orchestrator for workflow

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

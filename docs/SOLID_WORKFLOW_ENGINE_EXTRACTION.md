# SolidWorkflow Engine Extraction

## Context

The workflow system in Firefight is a generic, database-backed DAG orchestration engine. It has no knowledge of incidents, Slack, or any domain concept — it just provides a step DSL, dependency resolution, state machines, retry logic, and background execution via SolidQueue.

Extracting it into a Rails engine under `engines/solid_workflow/` makes the boundary explicit, enables reuse across future projects, and sets a precedent for future engine extractions (AI, integrations, etc.).

## What Moves Into the Engine

### Models (3)

| Current | Engine |
|---------|--------|
| `Workflow` | `SolidWorkflow::Workflow` |
| `WorkflowStep` | `SolidWorkflow::Step` |
| `WorkflowEvent` | `SolidWorkflow::Event` |

### Model Concerns (11)

| Current Path | Engine Path |
|-------------|-------------|
| `app/models/workflow/stateable.rb` | `engine/app/models/solid_workflow/workflow/stateable.rb` |
| `app/models/workflow/eventable.rb` | `engine/app/models/solid_workflow/workflow/eventable.rb` |
| `app/models/workflow/orchestratable.rb` | `engine/app/models/solid_workflow/workflow/orchestratable.rb` |
| `app/models/workflow/cancellable.rb` | `engine/app/models/solid_workflow/workflow/cancellable.rb` |
| `app/models/workflow/pausable.rb` | `engine/app/models/solid_workflow/workflow/pausable.rb` |
| `app/models/workflow/metrics.rb` | `engine/app/models/solid_workflow/workflow/metrics.rb` |
| `app/models/workflow_step/statusable.rb` | `engine/app/models/solid_workflow/step/statusable.rb` |
| `app/models/workflow_step/executable.rb` | `engine/app/models/solid_workflow/step/executable.rb` |
| `app/models/workflow_step/retryable.rb` | `engine/app/models/solid_workflow/step/retryable.rb` |
| `app/models/workflow_step/dependencies.rb` | `engine/app/models/solid_workflow/step/dependencies.rb` |
| `app/models/workflow_step/metrics.rb` | `engine/app/models/solid_workflow/step/metrics.rb` |

### Constants

| Current | Engine |
|---------|--------|
| `WorkflowEvents` (`app/models/concerns/workflow_events.rb`) | `SolidWorkflow::Events` |

### Base Class & Helpers

| Current | Engine |
|---------|--------|
| `Base` (`app/workflows/base.rb`) | `SolidWorkflow::Base` (`lib/solid_workflow/base.rb`) |
| `IdempotentSteps` (`app/workflows/idempotent_steps.rb`) | `SolidWorkflow::IdempotentSteps` (`lib/solid_workflow/idempotent_steps.rb`) |

### Jobs (3)

| Current | Engine |
|---------|--------|
| `Workflows::OrchestrateJob` | `SolidWorkflow::OrchestrateJob` |
| `Workflows::RunStepJob` | `SolidWorkflow::RunStepJob` |
| `Workflows::WorkflowSweeperJob` | `SolidWorkflow::SweeperJob` |

### Initializer

| Current | Engine |
|---------|--------|
| `config/initializers/workflows.rb` | Handled by `Engine` initializer |

## What Stays in the Host App

- All 8 concrete workflow classes (`app/workflows/*_workflow.rb`)
- All services, handlers, adapters, controllers
- All domain models (Incident, Workspace, etc.)
- Test fixtures and app-specific tests

## Engine Directory Structure

```
engines/solid_workflow/
├── app/
│   ├── jobs/
│   │   └── solid_workflow/
│   │       ├── orchestrate_job.rb
│   │       ├── run_step_job.rb
│   │       └── sweeper_job.rb
│   └── models/
│       └── solid_workflow/
│           ├── record.rb                  # Abstract base class
│           ├── workflow.rb
│           ├── workflow/
│           │   ├── stateable.rb
│           │   ├── eventable.rb
│           │   ├── orchestratable.rb
│           │   ├── cancellable.rb
│           │   ├── pausable.rb
│           │   └── metrics.rb
│           ├── step.rb
│           ├── step/
│           │   ├── statusable.rb
│           │   ├── executable.rb
│           │   ├── retryable.rb
│           │   ├── dependencies.rb
│           │   └── metrics.rb
│           ├── event.rb
│           └── events.rb                  # Event type constants
├── db/
│   └── migrate/
│       └── 20260225000001_create_solid_workflow_tables.rb
├── lib/
│   ├── solid_workflow.rb                  # Module + config
│   └── solid_workflow/
│       ├── engine.rb
│       ├── base.rb                        # Workflow DSL
│       ├── idempotent_steps.rb
│       └── version.rb
├── solid_workflow.gemspec
├── Gemfile
├── Rakefile
└── README.md
```

## Public API

### Defining Workflows

Identical DSL, just new base class:

```ruby
class IncidentCreationWorkflow < SolidWorkflow::Base
  workflow_name "incident.creation.v1"

  step :create_slack_channel
  step :set_channel_metadata, depends_on: [:create_slack_channel]

  def create_slack_channel(workflow:, step:, input:)
    service(workflow).create_channel(workflow.subject)
  end
end
```

### Starting Workflows

Unchanged:

```ruby
IncidentCreationWorkflow.start!(incident, context: { ... })
IncidentCreationWorkflow.start_inline!(incident)  # sync for tests/console
```

### Idempotent Steps

New module path:

```ruby
class MyWorkflow < SolidWorkflow::Base
  include SolidWorkflow::IdempotentSteps
end
```

### Host Model Associations

```ruby
class Incident < ApplicationRecord
  has_many :workflows, as: :subject, class_name: "SolidWorkflow::Workflow"
end
```

### Event Constants

```ruby
SolidWorkflow::Events::Workflow::SUCCEEDED
SolidWorkflow::Events::Step::FAILED
```

### Configuration

```ruby
SolidWorkflow.configure do |config|
  config.queue_name = :workflows
  config.stuck_workflow_threshold = 5.minutes
  config.orphaned_step_threshold = 10.minutes
  config.max_default_attempts = 5
  config.default_backoff = "exponential"
end
```

## Engine Internals

- `SolidWorkflow::Record` — abstract base inheriting `ActiveRecord::Base` (not `ApplicationRecord`)
- Jobs inherit from `ActiveJob::Base` (not `ApplicationJob`)
- `isolate_namespace SolidWorkflow` keeps everything namespaced
- Engine initializer handles workflow class registration (replaces `config/initializers/workflows.rb`)

## Table Naming

Rename from generic to engine-namespaced:

| Current | Engine |
|---------|--------|
| `workflows` | `solid_workflow_workflows` |
| `workflow_steps` | `solid_workflow_steps` |
| `workflow_events` | `solid_workflow_events` |

Column rename in events: `workflow_step_id` → `step_id`

## Migration Strategy

### Existing App (this codebase)

Single host-app migration renames tables and column. Zero data loss:

```ruby
class MigrateToSolidWorkflowEngine < ActiveRecord::Migration[8.1]
  def change
    rename_table :workflows, :solid_workflow_workflows
    rename_table :workflow_steps, :solid_workflow_steps
    rename_table :workflow_events, :solid_workflow_events
    rename_column :solid_workflow_events, :workflow_step_id, :step_id
  end
end
```

### New Installs

Engine ships a consolidated `create_solid_workflow_tables` migration:

```ruby
class CreateSolidWorkflowTables < ActiveRecord::Migration[8.1]
  def change
    create_table :solid_workflow_workflows, id: :uuid do |t|
      t.string :name, null: false
      t.string :workflow_class, null: false
      t.string :subject_type, null: false
      t.uuid :subject_id, null: false
      t.string :state, null: false, default: "pending"
      t.jsonb :context, null: false, default: {}
      t.jsonb :workflow_config, default: {}
      t.jsonb :state_timestamps, null: false, default: {}
      t.datetime :started_at
      t.datetime :completed_at
      t.string :cancelled_by
      t.text :cancellation_reason
      t.timestamps
      # indexes...
    end

    create_table :solid_workflow_steps, id: :uuid do |t|
      t.uuid :workflow_id, null: false
      t.string :name, null: false
      t.string :status, null: false, default: "pending"
      t.string :depends_on, array: true, default: []
      t.integer :position
      t.integer :attempts, null: false, default: 0
      t.integer :max_attempts, default: 5
      t.datetime :run_at
      t.datetime :started_at
      t.datetime :completed_at
      t.jsonb :input, null: false, default: {}
      t.jsonb :output, null: false, default: {}
      t.jsonb :retry_config
      t.text :last_error
      t.text :skip_reason
      t.timestamps
      # indexes...
    end

    create_table :solid_workflow_events, id: :uuid do |t|
      t.uuid :workflow_id, null: false
      t.uuid :step_id
      t.string :event_type, null: false
      t.jsonb :metadata, default: {}
      t.timestamps
      # indexes...
    end

    add_foreign_key :solid_workflow_steps, :solid_workflow_workflows, column: :workflow_id
    add_foreign_key :solid_workflow_events, :solid_workflow_workflows, column: :workflow_id
    add_foreign_key :solid_workflow_events, :solid_workflow_steps, column: :step_id
  end
end
```

## Files to Delete from Host App

After the engine has them:

```
app/models/workflow.rb
app/models/workflow_step.rb
app/models/workflow_event.rb
app/models/workflow/                       # entire directory
app/models/workflow_step/                  # entire directory
app/models/concerns/workflow_events.rb
app/workflows/base.rb
app/workflows/idempotent_steps.rb
app/jobs/workflows/orchestrate_job.rb
app/jobs/workflows/run_step_job.rb
app/jobs/workflows/workflow_sweeper_job.rb
config/initializers/workflows.rb
test/fixtures/workflows.yml
test/fixtures/workflow_steps.yml
test/fixtures/workflow_events.yml
```

## Host App Files to Update (~30 files)

### Workflow classes (8 files) — `< Base` → `< SolidWorkflow::Base`

```
app/workflows/incident_creation_workflow.rb
app/workflows/slack_workspace_setup_workflow.rb
app/workflows/lead_assignment_workflow.rb
app/workflows/incident_close_workflow.rb
app/workflows/incident_reopen_workflow.rb
app/workflows/incident_update_workflow.rb
app/workflows/summary_update_workflow.rb
app/workflows/example_calculation_workflow.rb
```

### Config (1 file) — update job class name

```
config/recurring.yml → Workflows::WorkflowSweeperJob → SolidWorkflow::SweeperJob
```

### Handler tests (6 files) — `Workflow.find_by!` → `SolidWorkflow::Workflow.find_by!`

```
test/services/interactions/set_lead_self_handler_test.rb
test/services/interactions/close_incident_handler_test.rb
test/services/interactions/incident_update_handler_test.rb
test/services/interactions/update_summary_handler_test.rb
test/services/interactions/reopen_incident_handler_test.rb
test/services/interactions/set_lead_handler_test.rb
```

### Model/job tests (6 files) — update all class references

```
test/models/workflow_test.rb
test/models/workflow_step_test.rb
test/models/workflow_event_test.rb
test/integration/workflow_execution_test.rb
test/jobs/workflows/orchestrate_job_test.rb
test/jobs/workflows/run_step_job_test.rb
```

## Implementation Order

1. Scaffold engine skeleton (gemspec, lib, engine.rb, Gemfile reference)
2. Move models + concerns + Events constants into engine
3. Move Base DSL, IdempotentSteps, and 3 jobs into engine
4. Create engine install migration + host app rename migration
5. Update host app workflow classes, recurring.yml, delete moved files
6. Update all tests to use engine namespaces
7. Run `bin/ci` to validate everything

## Verification

1. `bin/ci` passes (rubocop, brakeman, bundler-audit, tests, system tests, seeds)
2. `rails console` — `SolidWorkflow::Workflow.count` works
3. `rails console` — `IncidentCreationWorkflow.start_inline!(Incident.first)` succeeds
4. `SolidWorkflow::Base.registry` contains all 8 workflow classes
5. Recurring sweeper job references resolve: `SolidWorkflow::SweeperJob`

# WorkflowSweeperJob Documentation

## Overview

`WorkflowSweeperJob` is a **safety net and recovery mechanism** for the SolidWorkflow system. It runs periodically (typically every 5 minutes) to detect and automatically fix workflow issues that can occur in production environments.

## Purpose

In distributed systems, things can fail unexpectedly:
- Servers crash
- Workers die mid-execution
- Network issues cause timeouts
- Containers get evicted
- Out of memory errors kill processes

The sweeper ensures that workflows **eventually complete** even when infrastructure fails.

## What It Does

The sweeper handles two critical failure scenarios:

### 1. Stuck Workflows
Workflows that have stopped progressing due to infrastructure failures

### 2. Orphaned Steps
Steps stuck in "running" status because the worker crashed during execution

---

## Stuck Workflows

### Problem

Workflows can get "stuck" in a pending or running state when the orchestrator fails to run. This happens when:

- **Server crashes** during orchestration
- **Database transaction rollback** prevents orchestrator from completing
- **Job queue issues** prevent OrchestrateJob from running
- **Race conditions** cause orchestration to skip
- **Deployment restarts** interrupt job processing

### Example Scenario

```
1. Step A completes successfully ✓
2. RunStepJob calls workflow.enqueue_next_steps_later
3. Server crashes before OrchestrateJob runs ❌
4. Workflow is now "stuck":
   - Step A is complete
   - Step B is ready to run
   - But Step B never gets scheduled
5. Sweeper detects this and resumes the workflow ✓
```

### How It Works

```ruby
def sweep_stuck_workflows
  Workflow.where(state: %w[pending running])      # Active workflows
    .where("updated_at < ?", 5.minutes.ago)       # Haven't updated recently
    .find_each do |workflow|

      Rails.logger.info("Sweeper resuming workflow", workflow_id: workflow.id)
      workflow.enqueue_next_steps                 # Trigger orchestration
    end
end
```

**Detection Logic:**
1. Find all workflows in `pending` or `running` state
2. Filter to those that haven't updated in **5+ minutes** (abnormally stale)
3. Call `enqueue_next_steps` to trigger orchestration

**Why It's Safe:**
- The orchestrator uses **advisory locks** (`with_lock`)
- Safe to call `enqueue_next_steps` multiple times
- If steps aren't actually ready, nothing happens
- If steps are ready, they get scheduled

**Timeframe:**
- **5 minutes** is chosen because orchestration is quick
- Normal workflows update frequently as steps complete
- 5 minutes without updates indicates a problem

---

## Orphaned Steps

### Problem

Steps can become "orphaned" when the worker process dies while executing them. This happens when:

- **Worker process crashes** (segfault, killed by OS)
- **Server dies** during step execution
- **Container is killed** (e.g., Kubernetes pod eviction)
- **Out of memory error** kills the worker
- **Network timeout** causes worker to hang then crash

The step remains stuck in `"running"` status forever because no process is actually working on it.

### Example Scenario

```
1. Step "create_slack_channel" starts executing
2. Status changes to "running" ✓
3. Worker makes API call to Slack
4. Worker crashes due to OOM error ❌
5. Step stuck forever:
   - Status: "running"
   - But no worker is actually working on it
   - Workflow can never complete
6. Sweeper detects this after 10 minutes and resets the step ✓
```

### How It Works

```ruby
def sweep_orphaned_steps
  WorkflowStep.where(status: "running")           # Steps marked as running
    .where("updated_at < ?", 10.minutes.ago)      # But stale (10+ min)
    .find_each do |step|

      Rails.logger.warn("Sweeper resetting orphaned step", step_id: step.id)

      step.update!(
        status: "pending",                        # Reset to pending
        last_error: "Step was running but worker appears to have crashed (reset by sweeper)"
      )

      step.workflow.record_event(WorkflowEvents::Step::RESET, step: step, reason: "sweeper")
    end
end
```

**Detection Logic:**
1. Find all steps with status `"running"`
2. Filter to those that haven't updated in **10+ minutes**
3. Reset step to `"pending"` status
4. Add explanatory error message
5. Record a `RESET` event for audit trail
6. Next orchestrator run will retry the step

**Important:** The sweeper does **NOT** increment the `attempts` counter. The existing retry logic still applies, so `max_attempts` is still respected.

**Why It's Safe:**
- Step methods should be **idempotent** (per SolidWorkflow best practices)
- The retry count is NOT incremented by the sweeper
- Normal retry logic and backoff still apply
- Won't create infinite loops

**Timeframe:**
- **10 minutes** allows steps to complete legitimate long-running work
- Most steps complete in seconds/minutes
- 10 minutes without updates strongly suggests a crashed worker

---

## Configuration

### Scheduling with Solid Queue

Add to your `config/queue.yml`:

```yaml
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
      schedule: "*/5 * * * *"  # Run every 5 minutes
```

### Timeframe Configuration

The timeframes are currently hardcoded but can be made configurable:

```ruby
# config/initializers/solid_workflow.rb
SolidWorkflow.configure do |config|
  config.sweeper_stuck_workflow_threshold = 5.minutes
  config.sweeper_orphaned_step_threshold = 10.minutes
end
```

---

## Monitoring

### Logs

The sweeper logs all recovery actions:

**Stuck Workflow Resumed:**
```
[INFO] Sweeper resuming workflow workflow_id=abc-123
```

**Orphaned Step Reset:**
```
[WARN] Sweeper resetting orphaned step step_id=def-456
```

### Metrics to Track

Monitor these metrics in production:

1. **Sweeper executions per day**
   - Normal: 288 (every 5 min × 24 hours)

2. **Stuck workflows detected**
   - Should be rare in stable environment
   - Spike indicates infrastructure issues

3. **Orphaned steps detected**
   - Should be very rare
   - Indicates worker crashes or resource issues

4. **Steps reset multiple times**
   - Same step reset repeatedly = bug in step logic
   - Check for non-idempotent operations

### Alerting Recommendations

Set up alerts for:

```ruby
# Alert if sweeper finds >10 stuck workflows in 1 hour
if WorkflowEvent.where(event_type: "workflow.resumed_by_sweeper")
                .where("created_at > ?", 1.hour.ago).count > 10
  alert("High number of stuck workflows detected")
end

# Alert if same step is reset multiple times
if WorkflowEvent.where(event_type: "step.reset")
                .where("metadata->>'reason' = ?", "sweeper")
                .group("workflow_step_id")
                .having("count(*) > 3").any?
  alert("Step being repeatedly reset - possible bug")
end
```

---

## Troubleshooting

### High Number of Stuck Workflows

**Symptoms:**
- Many workflows being resumed by sweeper
- Workflows taking longer than expected

**Possible Causes:**
1. Job queue overwhelmed
2. Database connection pool exhausted
3. Advisory lock contention
4. OrchestrateJob not running

**Investigation:**
```ruby
# Check Solid Queue status
SolidQueue::Job.where(queue_name: "workflows").group(:status).count

# Check for lock contention
Workflow.where(state: "running").count

# Check orchestrator job delays
SolidQueue::Job.where(class_name: "Workflows::OrchestrateJob")
  .where("scheduled_at < ?", 5.minutes.ago).count
```

### High Number of Orphaned Steps

**Symptoms:**
- Many steps being reset by sweeper
- Steps timing out or hanging

**Possible Causes:**
1. Worker crashes (OOM, segfault)
2. External API timeouts
3. Resource constraints (CPU, memory)
4. Container evictions

**Investigation:**
```ruby
# Check which steps are commonly orphaned
WorkflowEvent.where(event_type: "step.reset")
  .where("metadata->>'reason' = ?", "sweeper")
  .joins(:workflow_step)
  .group("workflow_steps.name")
  .count

# Check step execution times
WorkflowStep.where(status: "succeeded")
  .where("completed_at > ?", 1.day.ago)
  .average("EXTRACT(EPOCH FROM (completed_at - started_at))")
```

### Same Step Repeatedly Reset

**Symptoms:**
- Specific step reset multiple times
- Workflow never completes

**Likely Cause:**
- Step is **not idempotent**
- Step has a bug causing crashes
- External service is broken

**Fix:**
```ruby
# 1. Check step logs
WorkflowEvent.where(workflow_step_id: step_id).order(:created_at)

# 2. Make step idempotent
def my_step(workflow:, step:, input:)
  # Check if work already done
  return { result: cached_value } if already_completed?

  # Do work
  result = perform_work

  # Cache result
  save_result(result)

  { result: result }
end

# 3. Add better error handling
def my_step(workflow:, step:, input:)
  retry_count = 0

  begin
    external_api_call
  rescue Timeout::Error => e
    retry_count += 1
    raise if retry_count > 3
    sleep(2 ** retry_count)
    retry
  end
end
```

---

## Performance Impact

### Database Load

The sweeper runs two queries every 5 minutes:

```sql
-- Stuck workflows query
SELECT * FROM workflows
WHERE state IN ('pending', 'running')
  AND updated_at < NOW() - INTERVAL '5 minutes';

-- Orphaned steps query
SELECT * FROM workflow_steps
WHERE status = 'running'
  AND updated_at < NOW() - INTERVAL '10 minutes';
```

**Impact:** Minimal
- Queries are indexed (`state`, `status`, `updated_at`)
- Most of the time finds 0-1 records
- Uses `find_each` for batching if many records

### Job Queue Load

- Adds 1 job every 5 minutes
- If stuck workflows found, adds orchestration jobs
- Normal load: negligible
- Recovery load: proportional to stuck workflows (temporary spike)

---

## Best Practices

### 1. Make Steps Idempotent

Always design steps to be safely retryable:

```ruby
# ❌ BAD - Not idempotent
def create_channel(workflow:, step:, input:)
  SlackClient.create_channel("incident-#{workflow.subject.id}")
end

# ✅ GOOD - Idempotent
def create_channel(workflow:, step:, input:)
  incident = workflow.subject

  # Check if already created
  return { channel_id: incident.slack_channel_id } if incident.slack_channel_id

  # Check if exists in Slack
  existing = SlackClient.find_channel_by_name("incident-#{incident.id}")
  if existing
    incident.update!(slack_channel_id: existing)
    return { channel_id: existing }
  end

  # Create new
  channel_id = SlackClient.create_channel("incident-#{incident.id}")
  incident.update!(slack_channel_id: channel_id)

  { channel_id: channel_id }
end
```

### 2. Keep Steps Short

Long-running steps are more likely to be interrupted:

```ruby
# ❌ BAD - One long step
def process_all_users(workflow:, step:, input:)
  User.find_each do |user|
    # 10 minutes of processing
  end
end

# ✅ GOOD - Break into smaller steps
step :fetch_user_ids
step :process_batch_1, depends_on: [:fetch_user_ids]
step :process_batch_2, depends_on: [:fetch_user_ids]
```

### 3. Add Timeouts

Prevent steps from hanging indefinitely:

```ruby
def call_external_api(workflow:, step:, input:)
  Timeout.timeout(30.seconds) do
    ExternalAPI.call(...)
  end
rescue Timeout::Error => e
  Rails.logger.error("API timeout", workflow_id: workflow.id)
  raise # Let retry logic handle it
end
```

### 4. Monitor Sweeper Activity

Track how often the sweeper finds issues:

```ruby
# Add metrics
def sweep_stuck_workflows
  count = 0
  Workflow.where(state: %w[pending running])
    .where("updated_at < ?", 5.minutes.ago)
    .find_each do |workflow|
      count += 1
      Rails.logger.info("Sweeper resuming workflow", workflow_id: workflow.id)
      workflow.enqueue_next_steps
    end

  Metrics.gauge("workflow.sweeper.stuck_workflows", count)
end
```

---

## Testing

### Unit Tests

```ruby
RSpec.describe WorkflowSweeperJob do
  describe "#sweep_stuck_workflows" do
    it "resumes workflows stuck for >5 minutes" do
      workflow = create(:workflow, state: :running, updated_at: 10.minutes.ago)

      expect(workflow).to receive(:enqueue_next_steps)

      described_class.new.perform
    end

    it "ignores recently updated workflows" do
      workflow = create(:workflow, state: :running, updated_at: 1.minute.ago)

      expect(workflow).not_to receive(:enqueue_next_steps)

      described_class.new.perform
    end
  end

  describe "#sweep_orphaned_steps" do
    it "resets steps stuck in running for >10 minutes" do
      step = create(:workflow_step, status: :running, updated_at: 15.minutes.ago)

      described_class.new.perform

      expect(step.reload.status).to eq("pending")
      expect(step.last_error).to include("worker appears to have crashed")
    end

    it "records reset event" do
      step = create(:workflow_step, status: :running, updated_at: 15.minutes.ago)

      expect {
        described_class.new.perform
      }.to change { step.workflow.workflow_events.where(event_type: "step.reset").count }.by(1)
    end
  end
end
```

### Integration Tests

Test recovery scenarios:

```ruby
RSpec.describe "Workflow recovery" do
  it "recovers from server crash during orchestration" do
    workflow = TestWorkflow.start!(subject)

    # Simulate first step completing
    step = workflow.workflow_steps.first
    step.execute!

    # Simulate crash before orchestration runs
    # (don't call enqueue_next_steps)

    # Fast-forward time
    travel 6.minutes

    # Run sweeper
    WorkflowSweeperJob.new.perform

    # Verify workflow resumes
    perform_enqueued_jobs

    expect(workflow.reload.state).to eq("succeeded")
  end
end
```

---

## Summary

The `WorkflowSweeperJob` is a critical component for production reliability:

✅ **Recovers stuck workflows** when orchestration fails
✅ **Resets orphaned steps** when workers crash
✅ **Uses safe, idempotent operations**
✅ **Provides visibility** through logging and events
✅ **Minimal performance impact**

It ensures that workflows **eventually complete** even in the face of infrastructure failures, making SolidWorkflow production-ready and resilient.

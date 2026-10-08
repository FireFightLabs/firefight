# Jobs run on the test adapter, so the test database has no Solid Queue tables. A test of how the queue treats a stopped
# worker makes them inside its own transaction, and the rollback takes them away again.
module QueueTablesHelper
  def with_queue_tables
    SolidQueue::Record.connection.schema_cache.clear!
    ActiveRecord::Migration.suppress_messages { load Rails.root.join("db/queue_schema.rb") }
    SolidQueue::Record.descendants.each(&:reset_column_information)
    yield
  ensure
    SolidQueue::Record.connection.schema_cache.clear!
  end

  # A worker that took the job and then stopped beating, as one killed by a deploy past its grace period does. Solid
  # Queue's own pruning then fails the job with a process error.
  def kill_worker_holding(job)
    worker = SolidQueue::Process.register(kind: "Worker", pid: rand(1..99_999), name: "worker-#{SecureRandom.hex(4)}", hostname: "test")
    SolidQueue::ReadyExecution.claim(job.queue_name, 1, worker.id)
    worker.update_columns(last_heartbeat_at: (SolidQueue.process_alive_threshold + 1.minute).ago)
    SolidQueue::Process.prune
    job.reload
  end
end

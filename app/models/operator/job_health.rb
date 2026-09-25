module Operator
  # Reads Solid Queue for the overview, jobs finished in the window, failed jobs still held, waiting jobs, and live
  # workers. The queue has its own database. When it cannot be read, read returns nil and the page says so.
  class JobHealth
    # A queue whose oldest ready job has waited this long counts as backed up.
    BACKED_UP_AFTER = 2.minutes

    Queue = Data.define(:name, :waiting, :oldest_at)
    FailedKind = Data.define(:job_class, :count, :last_at)

    attr_reader :finished, :failed, :failed_kinds, :waiting, :oldest_waiting_at, :workers, :workers_alive, :backed_up

    # Checks the table exists first, because a failed query would abort the caller's transaction.
    def self.read(since:)
      return nil unless SolidQueue::Job.table_exists?

      new(since)
    rescue ActiveRecord::ActiveRecordError => error
      Rails.logger.warn({ event: "operator.job_health_unreadable", error: error.class.name, message: error.message }.to_json)
      nil
    end

    def initialize(since)
      @finished = SolidQueue::Job.where(finished_at: since..).count
      read_failures
      read_waiting
      read_workers
    end

    private

    def read_failures
      rows = SolidQueue::FailedExecution.joins(:job).group("solid_queue_jobs.class_name")
                                        .pluck("solid_queue_jobs.class_name", Arel.sql("COUNT(*)"), Arel.sql("MAX(solid_queue_failed_executions.created_at)"))
      @failed_kinds = rows.map { |job_class, count, last_at| FailedKind.new(job_class:, count:, last_at:) }.sort_by { |kind| -kind.count }
      @failed = @failed_kinds.sum(&:count)
    end

    def read_waiting
      rows = SolidQueue::ReadyExecution.group(:queue_name).pluck(:queue_name, Arel.sql("COUNT(*)"), Arel.sql("MIN(created_at)"))
      queues = rows.map { |name, waiting, oldest_at| Queue.new(name:, waiting:, oldest_at:) }
      @waiting = queues.sum(&:waiting)
      @oldest_waiting_at = queues.filter_map(&:oldest_at).min
      @backed_up = queues.select { |queue| queue.oldest_at && queue.oldest_at < BACKED_UP_AFTER.ago }
    end

    def read_workers
      workers = SolidQueue::Process.where(kind: SolidQueue::Worker.name.demodulize)
      @workers = workers.count
      @workers_alive = workers.where(last_heartbeat_at: SolidQueue.process_alive_threshold.ago..).count
    end
  end
end

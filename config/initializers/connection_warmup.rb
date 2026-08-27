module ConnectionWarmup
  def self.enabled?
    ENV.fetch("CONNECTION_WARMUP", "true") == "true"
  end

  def self.run
    return unless enabled?

    warm_ar_pools
    warm_slack_pool
  end

  def self.warm_ar_pools
    ActiveRecord::Base.connection_handler.connection_pool_list.each do |pool|
      pool.with_connection { |c| c.execute("SELECT 1") }
    rescue StandardError => e
      Rails.logger.warn({
        event: "connection_warmup.ar_failed",
        pool: pool.db_config&.name,
        error: e.message
      })
    end
  end

  # Instantiates the Slack persistent pool eagerly so the first request
  # doesn't race the lazy init under concurrent Puma threads. Per-thread TCP
  # sockets are still opened lazily, only the pool object is materialized.
  def self.warm_slack_pool
    Slack::Client.http_pool
  rescue StandardError => e
    Rails.logger.warn({ event: "connection_warmup.slack_pool_failed", error: e.message })
  end
end

# Runs once per process after all initializers, covers Puma workers (forked
# via Phased Restart or boot), SolidQueue workers, console, rake tasks.
# Single entry point so we don't double-warm.
Rails.application.config.after_initialize do
  ConnectionWarmup.run
end

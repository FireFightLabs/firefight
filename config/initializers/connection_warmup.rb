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

  # Builds the Slack pool object before the first request so concurrent Puma threads do not race
  # its lazy init. Sockets still open lazily.
  def self.warm_slack_pool
    Slack::Client.http_pool
  rescue StandardError => e
    Rails.logger.warn({ event: "connection_warmup.slack_pool_failed", error: e.message })
  end
end

# after_initialize runs once per process, covering Puma workers, SolidQueue workers, console and rake.
Rails.application.config.after_initialize do
  ConnectionWarmup.run
end

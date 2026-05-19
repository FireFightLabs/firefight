module ConnectionWarmup
  def self.enabled?
    ENV.fetch("CONNECTION_WARMUP", "true") == "true"
  end

  def self.run
    return unless enabled?

    ActiveRecord::Base.connection_handler.connection_pool_list.each do |pool|
      pool.with_connection { |c| c.execute("SELECT 1") }
    rescue StandardError => e
      Rails.logger.warn({
        event: "connection_warmup.failed",
        pool: pool.db_config&.name,
        error: e.message
      })
    end
  end
end

unless ENV["SOLID_QUEUE_IN_PUMA"]
  SolidQueue.on_worker_start do
    ConnectionWarmup.run
  end
end

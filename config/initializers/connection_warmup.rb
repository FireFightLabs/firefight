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

# Run at the end of app boot. Fires once per process, after all initializers.
# Works in any Rails process — Puma worker, SolidQueue worker, console, etc.
# Critically, this runs *after* Rails has finished booting, so it actually has
# access to the connection pools (unlike Puma's `on_worker_boot`, which fires
# before app load when `preload_app!` is not set — leaving ConnectionWarmup
# undefined and silently skipping).
Rails.application.config.after_initialize do
  ConnectionWarmup.run
end

unless ENV["SOLID_QUEUE_IN_PUMA"]
  SolidQueue.on_worker_start do
    ConnectionWarmup.run
  end
end

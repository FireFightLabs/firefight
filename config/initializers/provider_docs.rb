# A fresh install has no providers' documentation yet, so when its job runner starts it reads the sources never read in
# the background, and the daily refresh keeps them current. Without a network the job fails quietly and Halon works
# from its skills alone, saying the documentation is not available.
Rails.application.config.after_initialize do
  SolidQueue.on_start do
    ProviderDocsSyncJob.perform_later(true) if ProviderDocSource.unread_keys.any?
  rescue ActiveRecord::ActiveRecordError => error
    Rails.logger.warn({ event: "provider_docs.first_fill_skipped", error: error.class.name }.to_json)
  end
end

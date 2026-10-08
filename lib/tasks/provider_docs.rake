namespace :provider_docs do
  desc "Read providers' documentation into the docs store now, printing progress: bin/rails provider_docs:sync [SOURCE=key] [UNREAD=1]"
  task sync: :environment do
    source = ENV["SOURCE"].presence
    if source && !ProviderDocSource::Definition.find(source)
      abort "No source named #{source}. Sources: #{ProviderDocSource::Definition.all.map(&:key).join(', ')}"
    end

    unread_only = ActiveModel::Type::Boolean.new.cast(ENV["UNREAD"]) || false
    if unread_only && (source ? ProviderDocSource.unread_keys.exclude?(source) : ProviderDocSource.unread_keys.empty?)
      next puts("#{source || 'Every source'} has been read already.")
    end

    ProviderDocsSyncJob.perform_now(unread_only, source: source, progress: ProviderDocs::Progress.new(out: $stdout))
  end
end

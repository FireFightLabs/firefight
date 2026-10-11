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

  desc "Check each provider's key reads against the docs store and close its API skill with them: bin/rails provider_docs:api_indexes [PROVIDER=key] [CHECK=1]"
  task api_indexes: :environment do
    provider = ENV["PROVIDER"].presence
    check = ActiveModel::Type::Boolean.new.cast(ENV["CHECK"]) || false
    indexes = Integrations::ApiIndex.all.select { |index| provider.nil? || index.provider == provider }
    abort "No API index for #{provider}. Indexes: #{Integrations::ApiIndex.all.map(&:provider).join(', ')}" if indexes.empty?

    results = indexes.map { |index| Integrations::ApiIndex::Refresh.new(index).run(write: !check) }
    results.each do |result|
      index = result.index
      puts "#{index.provider}: #{index.reads.size} reads, taken from #{index.source}, which the docs store does not hold, so not checked." unless index.reference
      result.dropped.each { |dropped| puts "#{index.provider}: the reference lists no query parameter #{dropped}, so it was left out." }
      result.stale.each { |call| puts "#{index.provider}: STALE #{call} is not in the reference the docs store holds. Replace or remove it." }
      changed = result.changed.map { |path| Pathname(path).relative_path_from(Rails.root) }.join(" and ")
      puts "#{index.provider}: #{check || result.stale? ? 'would change' : 'changed'} #{changed}" if result.changed.any?
    end
    failed = results.select { |result| result.stale? || (check && result.changed.any?) }
    abort "#{failed.map { |result| result.index.provider }.to_sentence} out of step with the docs store." if failed.any?
    puts "Every API index is in step with the docs store."
  end
end

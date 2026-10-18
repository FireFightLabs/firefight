namespace :search do
  desc "Write a similarity search vector for every incident, finding and postmortem that has none, a batch at a time"
  task backfill_embeddings: :environment do
    SearchEmbeddingBackfillJob.perform_later
    puts "Queued. Each batch of #{SearchEmbeddingBackfillJob::BATCH} queues the next one #{SearchEmbeddingBackfillJob::PAUSE.inspect} later, " \
         "and running this again picks up only what still has no vector."
  end
end

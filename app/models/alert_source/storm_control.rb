# What a source may send before Firefight refuses it, the same on every
# ingest path. Counts alerts rather than requests, so a batch cannot smuggle
# unbounded work past the limit.
module AlertSource::StormControl
  extend ActiveSupport::Concern

  MAX_PAYLOAD_BYTES = 512.kilobytes
  MAX_BATCH_ITEMS = 100
  RATE_WINDOW = 1.minute

  def payload_too_large?(bytesize)
    bytesize > MAX_PAYLOAD_BYTES
  end

  def batch_too_large?(item_count)
    item_count > MAX_BATCH_ITEMS
  end

  # Admits the items into this minute's budget, or refuses them all so a
  # runaway source is retried by its provider instead of saturating everyone.
  def admit?(item_count)
    key = "alerts:rate:#{id}:#{Time.current.to_i / RATE_WINDOW.to_i}"
    count = Rails.cache.increment(key, item_count, expires_in: RATE_WINDOW * 2)
    count.nil? || count <= rate_limit_per_minute
  end
end

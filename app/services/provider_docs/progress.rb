module ProviderDocs
  # Says what a docs refresh is doing while it runs. Each step is one JSON line in the log and, given a terminal, one plain
  # line there too, so a person running it by hand reads the same steps the log records. Reading a large source takes
  # minutes, so while it reads it reports every PAGES_EVERY pages or EVERY seconds, whichever comes first.
  class Progress
    PAGES_EVERY = 50
    CHUNKS_EVERY = 1_000
    EVERY = 15

    def initialize(out: nil, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @out = out
      @clock = clock
      @width = 0
      @totals = Hash.new(0)
    end

    def started(keys)
      @began = @clock.call
      @width = keys.map(&:length).max.to_i
      emit(:info, { event: "provider_docs.started", sources: keys.size }, "Reading #{count(keys.size, 'source')}")
    end

    def source_started(key)
      @source = key
      @source_began = @clock.call
      @tally = Hash.new(0)
      @total = nil
    end

    # How many pages the source will read, once it has listed them.
    def listed(total)
      @total = total
      @last = @clock.call
      emit(:info, { event: "provider_docs.source_started", source: @source, pages: total }, "#{label}reading #{count(total, 'page')}")
    end

    # One page done, as :changed, :unchanged, :failed or :left_out.
    def page(outcome)
      @tally[outcome] += 1
      done = @tally.values.sum
      return unless done < @total.to_i && ((done % PAGES_EVERY).zero? || due?)

      @last = @clock.call
      emit(:info, { event: "provider_docs.reading", source: @source, read: done, pages: @total, unchanged: @tally[:unchanged], failed: @tally[:failed] },
           "#{label}reading #{done}/#{@total} pages#{reading_detail}")
    end

    def source_finished(source, chunks:)
      seconds = elapsed(@source_began)
      failed = source.error.present?
      @totals[:read] += 1
      @totals[:pages] += source.page_count.to_i
      @totals[:chunks] += chunks
      emit(:info, { event: "provider_docs.read", source: @source, pages: source.page_count, version: source.version, chunks: chunks,
                    unchanged: @tally[:unchanged], pages_failed: @tally[:failed], failed: failed, seconds: seconds },
           "#{label}done, #{count(source.page_count.to_i, 'page')}, #{count(chunks, 'chunk')} written#{reading_detail} in #{duration(seconds)}")
    end

    def source_failed(error)
      @totals[:unread] += 1
      emit(:warn, { event: "provider_docs.unread", source: @source, error: error.message.truncate(300), seconds: elapsed(@source_began) },
           "#{label}could not be read: #{error.message.squish.truncate(300)}")
    end

    def embedding_started(total)
      @embed_began = @last = @clock.call
      @embed_total = total
      emit(:info, { event: "provider_docs.embedding", chunks: total }, "Embedding #{count(total, 'chunk')}")
    end

    def embedded(done)
      return unless done < @embed_total && ((done % CHUNKS_EVERY).zero? || due?)

      @last = @clock.call
      emit(:info, { event: "provider_docs.embedding", embedded: done, chunks: @embed_total }, "Embedding #{done}/#{@embed_total} chunks")
    end

    def embedding_finished(written)
      @totals[:embedded] = written
      seconds = elapsed(@embed_began)
      emit(:info, { event: "provider_docs.embedded", chunks: written, seconds: seconds }, "Embedded #{count(written, 'chunk')} in #{duration(seconds)}")
    end

    def embedding_failed(error)
      emit(:warn, { event: "provider_docs.unembedded", error: error.message.truncate(300) }, "Could not embed: #{error.message.squish.truncate(300)}")
    end

    # Each skill by name, with the guides it lists that the store does not hold.
    def missing_guides(guides)
      listed = guides.map { |skill, paths| "#{skill} (#{paths.join(', ')})" }.join(", ")
      emit(:warn, { event: "provider_docs.missing_guides", guides: guides }, "Guides skills list that the store does not hold: #{listed}")
    end

    def finished
      seconds = elapsed(@began)
      unread = @totals[:unread].positive? ? ", #{@totals[:unread]} could not be read" : ""
      emit(:info, { event: "provider_docs.finished", sources: @totals[:read], unread: @totals[:unread], pages: @totals[:pages],
                    chunks: @totals[:chunks], embedded: @totals[:embedded], seconds: seconds },
           "Done in #{duration(seconds)}: #{count(@totals[:read], 'source')} read#{unread}, #{count(@totals[:pages], 'page')}, " \
           "#{count(@totals[:chunks], 'chunk')} written, #{@totals[:embedded].to_fs(:delimited)} embedded")
    end

    private

    def emit(level, payload, line)
      Rails.logger.public_send(level, payload.to_json)
      return unless @out

      @out.puts(line)
      @out.flush
    end

    def due? = @clock.call - @last >= EVERY

    def label = "#{@source.to_s.ljust(@width)}  "

    def reading_detail
      parts = []
      parts << "#{@tally[:unchanged]} unchanged" if @tally[:unchanged].positive?
      parts << "#{@tally[:failed]} failed" if @tally[:failed].positive?
      parts.any? ? " (#{parts.join(', ')})" : ""
    end

    def elapsed(since) = since ? (@clock.call - since).round(1) : 0

    def count(number, noun) = "#{number.to_fs(:delimited)} #{noun.pluralize(number)}"

    def duration(seconds)
      minutes, rest = seconds.round.divmod(60)
      hours, minutes = minutes.divmod(60)
      return "#{hours}h #{minutes}m" if hours.positive?

      minutes.positive? ? "#{minutes}m #{rest}s" : "#{rest}s"
    end
  end
end

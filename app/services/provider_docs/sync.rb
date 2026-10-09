module ProviderDocs
  # Reads one source into the docs store. Pages it read are written and split into chunks again, pages it no longer
  # names are removed, and a page it could not read keeps the copy it had. A source that cannot be read at all keeps
  # every page and records why, so Halon never loses documentation to a bad day on the provider's side.
  class Sync
    READERS = {
      ProviderDocSource::Definition::KIND_REPOSITORY => Repository,
      ProviderDocSource::Definition::KIND_SITE => Site,
      ProviderDocSource::Definition::KIND_INDEX => Index,
      ProviderDocSource::Definition::KIND_PACKAGE => Package
    }.freeze
    FAILED_SHOWN = 5
    # What reading a source can fail with. The job rescues the same list, since a source that failed is already recorded.
    READ_ERRORS = [ DocsClient::Error, SystemCallError, JSON::ParserError, KeyError ].freeze

    def self.run!(definition, client: DocsClient.new, progress: Progress.new) = new(definition, client: client, progress: progress).run!

    def initialize(definition, client:, progress:)
      @definition = definition
      @client = client
      @progress = progress
    end

    def run!
      @progress.source_started(@definition.key)
      source = ProviderDocSource.for(@definition)
      reading = reader(source).read
      now = Time.current
      chunks = 0
      ProviderDocSource.transaction do
        reading.pages.select(&:content).each { |fetched| chunks += write(source, fetched, now) }
        source.pages.where.not(path: reading.listed).delete_all
        source.update!(version: reading.version, license: reading.license || source.license, page_count: source.pages.count,
                       fetched_at: now, checked_at: now, error: failures(reading.failed))
      end
      @progress.source_finished(source, chunks: chunks)
      source
    rescue *READ_ERRORS => error
      source&.failed!(error.message)
      @progress.source_failed(error)
      raise
    end

    private

    def reader(source)
      revisions = source.pages.pluck(:path, :revision).to_h
      options = { client: @client, revisions: revisions, progress: @progress }
      options[:version] = source.version if @definition.kind == ProviderDocSource::Definition::KIND_PACKAGE
      READERS.fetch(@definition.kind).new(@definition, **options)
    end

    # A page another source of the same provider held before moves to this one, so a path is only ever one page. Returns
    # how many chunks it wrote, none when its words did not change.
    def write(source, fetched, now)
      page = ProviderDocPage.find_or_initialize_by(provider: source.provider, path: fetched.path)
      digest = ProviderDocPage.digest_for(fetched.content)
      changed = page.content_digest != digest
      page.update!(source: source, url: fetched.url, title: ProviderDocPage.title_for(fetched.content, fetched.path),
                   content: fetched.content, content_digest: digest, revision: fetched.revision, fetched_at: now)
      changed ? page.rechunk! : 0
    end

    def failures(failed)
      return nil if failed.empty?

      shown = failed.first(FAILED_SHOWN).map { |path, reason| "#{path}: #{reason}" }
      more = failed.size > FAILED_SHOWN ? " and #{failed.size - FAILED_SHOWN} more" : ""
      "#{failed.size} #{'page'.pluralize(failed.size)} could not be read and kept the copy they had. #{shown.join('. ')}#{more}."
    end
  end
end

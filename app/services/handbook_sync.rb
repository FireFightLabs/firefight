# Keeps synced handbook pages in step with where they come from. A repository's file or folder is read through its code
# host when its default branch moves and on the hourly sweep, and a document in a connected tool is read on the sweep.
# Each file or document is one page. A page whose file is gone is taken away, and a read that fails keeps every page as
# it was and says why on the handbook.
class HandbookSync
  # How often the sweep reads a source again, whether or not a push said it changed.
  EVERY = 1.hour

  def self.pushed!(integrations, pushes)
    Chat::HandbookSource.where(integration: integrations, kind: Chat::HandbookSource::KIND_REPOSITORY).find_each do |source|
      HandbookSyncJob.perform_later(source.id) if pushes.any? { |push| source.moved_by?(push.repository, push.branch) }
    end
  end

  # Every source not read within EVERY.
  def self.sweep!(now: Time.current)
    Chat::HandbookSource.where("synced_at IS NULL OR synced_at < ?", now - EVERY).find_each { |source| HandbookSyncJob.perform_later(source.id) }
  end

  def initialize(source)
    @source = source
    @workspace = source.workspace
  end

  # Reads the source and writes its pages. Answers the pages it holds, or nil when the read failed.
  def sync!
    integration = @source.integration
    return failed("The connection this was synced through was removed or switched off.") unless integration && Integration.active.exists?(integration.id)

    read = read_source(integration)
    digest = Digest::SHA256.hexdigest(read.files.map { |file| "#{file[:path]}\n#{file[:text]}" }.join("\n\u0000"))
    # A read that found the same files changes nothing.
    refused = digest == @source.digest && @source.pages.any? ? [] : write_pages(read.files)
    @source.synced!(digest: digest, branch: read.branch, url: read.url, note: [ *read.gaps, *refused ].join(" ").presence)
    @source.pages.reload
  rescue Integrations::Error => error
    failed(error.message)
  end

  private

  Read = Data.define(:files, :branch, :url, :gaps)

  def read_source(integration)
    if @source.repository?
      found = Integrations::RepositoryDocuments.read(integration, repository: @source.repository, path: @source.path)
      files = found.files.map { |file| { path: file.path, text: file.content, url: file.url, title: nil } }
      Read.new(files: files, branch: found.branch, url: (files.first[:url] unless @source.folder?), gaps: found.gaps)
    else
      page = Integrations::Documents.read(integration, @source.reference)
      Read.new(files: [ { path: @source.reference, text: page.text, url: page.url, title: page.title } ], branch: nil, url: page.url, gaps: [])
    end
  end

  # One page per file, matched by its path, so a page keeps its place and history while its file changes. A file the
  # handbook refuses, such as one that looks like it holds a secret, keeps its page as it was. Answers why each was refused.
  def write_pages(files)
    existing = @source.pages.includes(:current_wording).index_by(&:source_path)
    refused = []
    kept = files.filter_map do |file|
      write_page(file, existing[file[:path]])
    rescue ActiveRecord::RecordInvalid => error
      refused << "#{file[:path]} was not brought in: #{error.record.errors.full_messages.to_sentence.downcase_first}."
      existing[file[:path]]
    end
    (existing.values - kept).each(&:destroy!)
    refused
  end

  def write_page(file, page)
    text = file[:text].to_s.strip.truncate(Chat::HandbookPage::TEXT_LIMIT)
    title = page_title(file, page)
    service = HandbookService.new(@workspace)
    return service.indexed!(Chat::HandbookPage.create_written!(@workspace, title: title, text: text, by: nil, kind: Chat::HandbookPage::KIND_SYNCED,
                                                                          source: @source, source_path: file[:path], source_url: file[:url])) unless page

    page.update!(source_url: file[:url], title: title) if page.source_url != file[:url] || page.title != title
    service.indexed!(page) if page.text != text && page.write!(text: text, by: nil)
    page
  end

  # The document's own title, else its first heading, else its file name, made unique beside the workspace's other pages.
  def page_title(file, page)
    wanted = file[:title].presence || file[:text].to_s[/^#\s+(.+)$/, 1].presence || ::File.basename(file[:path].to_s, ".*").tr("-_", "  ").squish.capitalize
    wanted = wanted.to_s.truncate(Chat::HandbookPage::TITLE_LIMIT - 20)
    taken = Chat::HandbookPage.where(workspace: @workspace).where.not(id: page&.id).pluck(:title).map(&:downcase).to_set
    return wanted unless taken.include?(wanted.downcase)

    (2..).lazy.map { |number| "#{wanted} (#{number})" }.find { |candidate| taken.exclude?(candidate.downcase) }
  end

  def failed(words)
    @source.failed!(words)
    nil
  end
end

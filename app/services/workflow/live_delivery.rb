# Tells open workflow pages which part of them changed (Workflow::LiveSignal), over WorkflowChannel. A busy run moves
# its steps many times a second, so each workflow and part is said at most once per WINDOW, as Incident::LiveDelivery
# does for an incident's page. The first change held back books one trailing say (WorkflowPageSignalJob) for after the
# window, which covers every change made before it runs. When each part was last said is kept for a while, so a page
# that starts listening is told only what changed since it was read (changed_since), rather than reading every part
# again just after it opened.
class Workflow::LiveDelivery
  WINDOW = 1.second
  # How long when a part was last said is kept. A page read longer ago than this reads every part when it listens.
  SAID_KEPT = 1.hour
  # Allows for the clocks of the server that read the page and the one that said a change being a little apart.
  CLOCK_MARGIN = 2.seconds
  # A part's note: when it was last said, or since when nothing has been.
  SAID = "said".freeze
  QUIET_SINCE = "quiet_since".freeze

  # Runs after the change committed, so a cache, queue or cable that is down is logged and never reaches whoever made
  # the change. An open page reads every part again when its socket next connects and that cannot be told.
  def self.changed(workflow_id:, part:)
    return say(workflow_id, part) if Rails.cache.write(gate_key(workflow_id, part), true, unless_exist: true, expires_in: WINDOW)
    return unless Rails.cache.write(trailing_key(workflow_id, part), true, unless_exist: true, expires_in: WINDOW)

    book_trailing(workflow_id, part)
  rescue StandardError => error
    Rails.logger.error({ event: "workflow_page.signal_failed", workflow_id: workflow_id, part: part, error: error.class.name, message: error.message }.to_json)
  end

  # The trailing say goes through the gate too, with its own booking cleared first so a held back say books the next.
  def self.trailing(workflow_id:, part:)
    Rails.cache.delete(trailing_key(workflow_id, part))
    changed(workflow_id: workflow_id, part: part)
  end

  # A booking whose job never queued is released, so the next change in the window books the trailing say again.
  def self.book_trailing(workflow_id, part)
    return if WorkflowPageSignalJob.set(wait: WINDOW).perform_later(workflow_id, part)

    Rails.cache.delete(trailing_key(workflow_id, part))
  rescue StandardError
    Rails.cache.delete(trailing_key(workflow_id, part))
    raise
  end

  # Noted before it is said, so a page that starts listening after the say still finds it.
  def self.say(workflow_id, part)
    Rails.cache.write(said_key(workflow_id, part), { SAID => Time.current.to_f }, expires_in: SAID_KEPT)
    ActionCable.server.broadcast(WorkflowChannel.stream_name(workflow_id), { part: part })
  end

  # Called before a page is read: each part with no note yet is noted as quiet from now, so a part with no note at all
  # is one that cannot be told (the note expired or the cache let it go) and never one taken to be unchanged.
  def self.watching(workflow_id)
    quiet = { QUIET_SINCE => Time.current.to_f }
    Workflow::LiveSignal::PARTS.each_value { |part| Rails.cache.write(said_key(workflow_id, part), quiet, unless_exist: true, expires_in: SAID_KEPT) }
  rescue StandardError => error
    Rails.logger.error({ event: "workflow_page.watching_failed", workflow_id: workflow_id, error: error.class.name, message: error.message }.to_json)
  end

  # The parts that may have changed since a page was read at read_at (epoch seconds): each said since, or whose note
  # cannot say, and every part when the page does not say when it was read, was read longer ago than SAID_KEPT or the
  # cache cannot be read.
  def self.changed_since(workflow_id, read_at)
    parts = Workflow::LiveSignal::PARTS.values
    return parts if read_at.nil? || read_at < SAID_KEPT.ago.to_f

    notes = Rails.cache.read_multi(*parts.map { |part| said_key(workflow_id, part) })
    parts.reject { |part| unchanged?(notes[said_key(workflow_id, part)], read_at) }
  rescue StandardError => error
    Rails.logger.error({ event: "workflow_page.changed_since_failed", workflow_id: workflow_id, error: error.class.name, message: error.message }.to_json)
    parts
  end

  # Said only before the page was read, or quiet since before then.
  def self.unchanged?(note, read_at)
    return false unless note.is_a?(Hash)
    return note[SAID] < read_at - CLOCK_MARGIN.to_f if note[SAID]

    note[QUIET_SINCE].present? && note[QUIET_SINCE] <= read_at
  end

  def self.gate_key(workflow_id, part) = "workflow_page/#{workflow_id}/#{part}"

  def self.trailing_key(workflow_id, part) = "workflow_page/#{workflow_id}/#{part}/trailing"

  def self.said_key(workflow_id, part) = "workflow_page/#{workflow_id}/#{part}/said_at"
end

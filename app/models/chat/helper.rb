# One narrow check Halon handed to a helper while it worked, such as the logs of one service, run at the same time as the
# others it started with one run_helpers call. It reads as whoever the chat or run acts for, never anyone with more reach,
# spends from the same budget, and keeps a chat of its own with every tool call it made. Every move out of running is one
# guarded update, so a stop, a lost worker and the report never end it twice.
class Chat::Helper < ApplicationRecord
  STATUS_RUNNING = "running"
  STATUS_REPORTED = "reported"
  STATUS_FAILED = "failed"
  STATUS_STOPPED = "stopped"
  STATUSES = [ STATUS_RUNNING, STATUS_REPORTED, STATUS_FAILED, STATUS_STOPPED ].freeze

  # Checks handed off in one call, all run at once.
  MAX_AT_ONCE = 4
  # Helpers one question to a chat, or one run, may start in all.
  MAX_PER_QUESTION = 8
  # Helpers running at once in a workspace, across every chat and run, so a storm of alerts cannot start dozens together.
  MAX_RUNNING_IN_WORKSPACE = 12
  TITLE_LIMIT = 60
  BRIEF_LIMIT = 1_000
  REPORT_LIMIT = 2_000

  # Why a helper ended without a report, in the words Halon and the person read.
  OUT_OF_BUDGET = "It ran out of the budget it was given before it could report.".freeze
  OUT_OF_TURNS = "It took too many steps without reporting.".freeze
  INTERRUPTED = "It was interrupted before it reported.".freeze
  STOPPED = "Stopped before it reported.".freeze
  COULD_NOT = "It could not run.".freeze

  belongs_to :chat
  belongs_to :workspace
  # The helper's own chat with the model, its tool calls included.
  has_one :own_chat, class_name: "Chat", as: :owner, dependent: :destroy

  encrypts :report

  validates :status, inclusion: { in: STATUSES }

  scope :running, -> { where(status: STATUS_RUNNING) }
  scope :in_order, -> { order(:created_at, :position) }

  def running? = status == STATUS_RUNNING

  def reported? = status == STATUS_REPORTED

  # Its own chat holds only the brief and the work, so a rebuild puts all of it away and starts again from the brief.
  def keeps_in_memory?(_message) = false

  def memory_brief = "Your brief, as Halon gave it: #{brief}"

  # Ends it once, from running. False when something else ended it first.
  def finish!(status, report: nil, ended_because: nil, turns_used: nil, spent_micros: nil)
    moved = self.class.where(id: id, status: STATUS_RUNNING).update_all(
      { status: status, ended_because: ended_because, finished_at: Time.current, updated_at: Time.current,
        turns_used: turns_used, spent_micros: spent_micros }.compact
    ) == 1
    update_column(:report, report.to_s.truncate(REPORT_LIMIT)) if moved && report.present?
    reload
    moved
  end

  # What each turn spent so far, kept as it goes so a page shows a helper's cost while it works.
  def spent!(turns_used:, spent_micros:)
    self.class.where(id: id).update_all(turns_used: turns_used, spent_micros: spent_micros, updated_at: Time.current)
  end

  # How it went, as Halon reads it back and as a rebuilt chat remembers it.
  def line
    said = reported? ? report : ended_because
    "- #{title}: #{said.presence || 'nothing reported'}"
  end

  # A helper still running when its asking call was closed as interrupted belongs to a worker that died.
  def self.interrupted!(chat, tool_call_ids)
    return 0 if tool_call_ids.empty?

    running.where(chat: chat, tool_call_id: tool_call_ids)
      .update_all(status: STATUS_FAILED, ended_because: INTERRUPTED, finished_at: Time.current, updated_at: Time.current)
  end

  # Over a limit, the sentence Halon reads. nil when there is room for count more.
  def self.full_reason(chat, count, since:)
    return "Hand off at most #{MAX_AT_ONCE} checks in one call." if count > MAX_AT_ONCE

    started = where(chat: chat).where(created_at: since..).count
    if started + count > MAX_PER_QUESTION
      return "Helpers already ran #{started} checks for this, and at most #{MAX_PER_QUESTION} run for one question. Read the rest yourself."
    end

    running_now = running.where(workspace_id: chat.workspace_id).count
    return nil if running_now + count <= MAX_RUNNING_IN_WORKSPACE

    "#{running_now} helpers are already running in this workspace, which is as many as run at once. Read these yourself, or hand off fewer."
  end

  # Claimed together under a lock per workspace, so two chats handing off at once cannot pass the workspace limit
  # between them. Returns the helpers, or the sentence that refused them.
  def self.start!(chat:, tool_call_id:, checks:, since:)
    transaction do
      key = Zlib.crc32("chat_helpers:#{chat.workspace_id}")
      connection.select_value(sanitize_sql_array([ "SELECT pg_advisory_xact_lock(?)::text", key ]))
      refused = full_reason(chat, checks.size, since: since)
      next refused if refused

      first = where(chat: chat, tool_call_id: tool_call_id).maximum(:position).to_i
      checks.each_with_index.map do |check, index|
        create!(
          chat: chat, workspace_id: chat.workspace_id, tool_call_id: tool_call_id, position: first + index + 1,
          title: check.title.to_s.squish.truncate(TITLE_LIMIT), brief: check.brief.to_s.strip.truncate(BRIEF_LIMIT),
          deep: check.deep, started_at: Time.current
        )
      end
    end
  end
end

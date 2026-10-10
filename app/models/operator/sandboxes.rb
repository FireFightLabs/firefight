module Operator
  # Every code sandbox and kept copy across providers, set against what the app recorded for them. What a provider holds
  # comes from the sweep's last reading (ProviderSandbox), what the app holds from CodeBox and PreparedCopy, so a box
  # nobody recorded, one left running too long, one that failed or one stuck starting or stopping stands out.
  class Sandboxes
    FLAG_ROGUE = "rogue".freeze
    FLAG_OVERDUE = "overdue".freeze
    FLAG_FAILED = "failed".freeze
    FLAG_STUCK = "stuck".freeze
    FLAG_MISSING = "missing".freeze
    FLAGS = [ FLAG_ROGUE, FLAG_OVERDUE, FLAG_FAILED, FLAG_STUCK, FLAG_MISSING ].freeze

    ORIGIN_INVESTIGATION = "investigation".freeze
    ORIGIN_CHAT = "chat".freeze
    ORIGIN_CODE_FIX = "code_fix".freeze
    ORIGIN_OTHER = "other".freeze
    ORIGINS = [ ORIGIN_INVESTIGATION, ORIGIN_CHAT, ORIGIN_CODE_FIX, ORIGIN_OTHER ].freeze

    # The timeline's window.
    WINDOW = 24.hours
    # No run keeps a box longer than this, idle or not.
    LONGEST_LIFE = 6.hours
    # Starting or stopping takes minutes. Past this a box is stuck there.
    STUCK_AFTER = 15.minutes
    # A box a provider holds with no record is left this long first, since the app writes its row once the box answers.
    UNRECORDED_GRACE = 15.minutes
    # A stopped box a provider still keeps is deleted within the hour. One kept past this is overdue.
    STOPPED_KEPT_FOR = 2.hours
    TIMELINE_LIMIT = 60

    ACTIVE = [ ProviderSandbox::PHASE_STARTING, ProviderSandbox::PHASE_RUNNING, ProviderSandbox::PHASE_STOPPING ].freeze
    PASSING = [ ProviderSandbox::PHASE_STARTING, ProviderSandbox::PHASE_STOPPING ].freeze

    Origin = Data.define(:kind, :label, :id)
    Box = Data.define(:key, :provider, :ref, :name, :size, :phase, :state, :started_at, :ended_at, :last_used_at, :workspace, :origin,
                      :seconds, :cost_micros, :flags, :recorded, :held)
    Copy = Data.define(:key, :provider, :ref, :purpose, :phase, :state, :workspace, :repository, :created_at, :last_used_at, :byte_size,
                       :monthly_micros, :flags)
    Read = Data.define(:provider, :read_at, :error)
    Totals = Data.define(:running, :today_micros, :month_micros, :failovers, :rogue)

    def initialize(now: Time.current)
      @now = now
    end

    def boxes
      @boxes ||= begin
        seen = ProviderSandbox.where(kind: ProviderSandbox::KIND_BOX).where("gone_at IS NULL OR gone_at >= ?", window_start).index_by { |row| [ row.provider, row.ref ] }
        records = CodeBox.includes(:workspace).where("stopped_at IS NULL OR stopped_at >= ?", window_start).index_by { |row| [ row.provider, row.box_ref ] }
        sessions = CodeAgentSession.where(box_key: records.values.map(&:key)).group_by(&:box_key)
        (seen.keys | records.keys).map { |pair| box(pair, seen[pair], records[pair], sessions) }
                                  .sort_by { |each| [ each.flags.empty? ? 1 : 0, -(each.started_at || @now).to_f ] }
      end
    end

    def copies
      @copies ||= begin
        seen = ProviderSandbox.where(kind: ProviderSandbox::KIND_SNAPSHOT, gone_at: nil).index_by { |row| [ row.provider, row.ref ] }
        kept = PreparedCopy.includes(:workspace).index_by { |row| row.kept_in == PreparedCopy::KEPT_IN_ARCHIVE ? [ row.kept_in, row.id ] : [ row.kept_in, row.kept_ref ] }
        (seen.keys | kept.keys).map { |pair| copy(pair, seen[pair], kept[pair]) }.sort_by { |each| [ each.flags.empty? ? 1 : 0, -(each.created_at || @now).to_f ] }
      end
    end

    def reads = SandboxProviderRead.order(:provider).map { |read| Read.new(SandboxProviders.name_of(read.provider), read.read_at, read.error) }

    def totals
      running = boxes.select { |each| ACTIVE.include?(each.phase) }.group_by(&:provider).transform_values(&:size)
      Totals.new(running, spent_since(@now.beginning_of_day), spent_since(@now.beginning_of_month),
                 CodeBox.where(created_at: window_start..).where.not(failed_over_from: nil).count,
                 rogue.size)
    end

    def rogue = boxes.select { |each| each.flags.include?(FLAG_ROGUE) } + copies.select { |each| each.flags.include?(FLAG_ROGUE) }

    def box_at(provider, ref) = boxes.find { |each| each.provider == provider && each.ref == ref }

    def copy_at(provider, ref) = copies.find { |each| each.provider == provider && each.ref == ref }

    def window_start = @now - WINDOW

    private

    def box(pair, seen, record, sessions)
      provider, ref = pair
      phase = seen ? (seen.gone_at ? ProviderSandbox::PHASE_STOPPED : seen.phase) : (record.stopped_at ? ProviderSandbox::PHASE_STOPPED : ProviderSandbox::PHASE_RUNNING)
      started = record&.box_started_at || record&.created_at || seen&.started_at || seen&.first_seen_at
      ended = record&.stopped_at || seen&.gone_at
      seconds = record ? seconds_run(record) : ((ended || @now) - (started || @now)).to_i.clamp(0..)
      Box.new("#{provider}:#{ref}", provider, ref, seen&.name, record&.size || seen&.size, phase, seen&.state, started, ended, record&.last_used_at,
              record&.workspace, record && origin(record, sessions[record.key]), seconds, record&.hourly_micros && cost(record),
              box_flags(seen, record, phase), record.present?, seen.present? && seen.gone_at.nil?)
    end

    def box_flags(seen, record, phase)
      flags = []
      live = record && record.stopped_at.nil?
      present = seen && seen.gone_at.nil?
      flags << FLAG_ROGUE if present && !live && ACTIVE.include?(phase) && seen.first_seen_at < UNRECORDED_GRACE.ago(@now)
      flags << FLAG_OVERDUE if live && (record.last_used_at < CodeBox::ABANDONED_AFTER.ago(@now) || (record.box_started_at || record.created_at) < LONGEST_LIFE.ago(@now))
      flags << FLAG_OVERDUE if present && !live && phase == ProviderSandbox::PHASE_STOPPED && (seen.provider_updated_at || seen.first_seen_at) < STOPPED_KEPT_FOR.ago(@now)
      flags << FLAG_FAILED if present && phase == ProviderSandbox::PHASE_FAILED
      flags << FLAG_STUCK if present && PASSING.include?(phase) && (seen.provider_updated_at || seen.first_seen_at) < STUCK_AFTER.ago(@now)
      flags << FLAG_MISSING if live && !present && read_since?(record.provider, record.created_at + UNRECORDED_GRACE)
      flags.uniq
    end

    def copy(pair, seen, kept)
      provider, ref = pair
      phase = seen ? seen.phase : ProviderSandbox::PHASE_READY
      purpose = seen&.purpose || ProviderSandbox::PURPOSE_PREPARED
      flags = []
      flags << FLAG_ROGUE if seen && !kept && purpose == ProviderSandbox::PURPOSE_PREPARED && seen.first_seen_at < UNRECORDED_GRACE.ago(@now)
      flags << FLAG_FAILED if seen && phase == ProviderSandbox::PHASE_FAILED
      flags << FLAG_STUCK if seen && phase == ProviderSandbox::PHASE_STARTING && seen.first_seen_at < STUCK_AFTER.ago(@now)
      flags << FLAG_MISSING if kept && !seen && provider != PreparedCopy::KEPT_IN_ARCHIVE && read_since?(provider, kept.created_at + UNRECORDED_GRACE)
      Copy.new("#{provider}:#{ref}", provider, kept&.kept_ref || ref.to_s, purpose, phase, seen&.state, kept&.workspace, kept&.repository,
               kept&.created_at || seen&.started_at || seen&.first_seen_at, kept&.last_used_at, seen&.byte_size || kept&.byte_size,
               seen&.monthly_micros.to_i, flags)
    end

    # The run, chat or code fix that holds the box, by the key each gives its box.
    def origin(record, sessions)
      session = Array(sessions).max_by(&:created_at)
      return Origin.new(ORIGIN_CODE_FIX, "Code fix in #{session.repository}", record.workspace_id) if session
      return Origin.new(ORIGIN_INVESTIGATION, "Investigation", record.key.delete_prefix(Investigation::CODE_BOX_PREFIX)) if record.key.start_with?(Investigation::CODE_BOX_PREFIX)
      return Origin.new(ORIGIN_CHAT, "Chat", record.key.delete_prefix(Conversation::CODE_BOX_PREFIX)) if record.key.start_with?(Conversation::CODE_BOX_PREFIX)

      Origin.new(ORIGIN_OTHER, record.key, nil)
    end

    def read_since?(provider, at) = SandboxProviderRead.where(provider: provider, error: nil).where(read_at: at..).exists?

    def seconds_run(record)
      return record.running_seconds if record.stopped_at

      record.running_seconds + (@now - (record.box_started_at || record.created_at)).to_i.clamp(0..)
    end

    def cost(record) = (record.hourly_micros * seconds_run(record) / 3600.0).round

    # Boxes started since, at their price, and what kept copies cost to store over the same days.
    def spent_since(from)
      compute = CodeBox.where(created_at: from..).where.not(hourly_micros: nil).sum { |record| cost(record) }
      days = ((@now - from) / 1.day).clamp(0, 31)
      storage = ProviderSandbox.where(kind: ProviderSandbox::KIND_SNAPSHOT, gone_at: nil).sum(:monthly_micros) * days / 30.0
      (compute + storage).round
    end
  end
end

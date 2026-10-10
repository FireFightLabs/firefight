module Operator
  # Where one workspace's code sandboxes run, which of them failed over, and what each code fix cost, read from what
  # the app records for itself (CodeBox, CodeAgentSession).
  class WorkspaceSandbox
    # The choice that holds the workspace to no provider, so it follows the deployment's main and backup.
    FOLLOW_DEPLOYMENT = "deployment".freeze
    LIMIT = 50

    Choice = Data.define(:value, :label)
    Failover = Data.define(:id, :at, :from, :to, :reason)
    Fix = Data.define(:id, :repository, :at, :ai_micros, :sandbox_micros, :sandbox_seconds, :providers, :pull_request_url)
    Row = Data.define(:workspace, :boxes, :failovers, :sandbox_micros)

    # Boxes started in the window, priced at what each one's provider charges for its size by the hour.
    COST_SQL = <<~SQL.squish.freeze
      COALESCE(SUM(code_boxes.hourly_micros * (code_boxes.running_seconds + CASE WHEN code_boxes.stopped_at IS NULL
        THEN GREATEST(0, EXTRACT(EPOCH FROM (now() - COALESCE(code_boxes.box_started_at, code_boxes.created_at)))) ELSE 0 END) / 3600.0), 0)
    SQL

    # Every workspace, with its boxes, failovers and sandbox spend in the window, in one query for the boxes.
    def self.rows(filter, workspaces)
      totals = CodeBox.where(workspace_id: workspaces.map(&:id), created_at: filter.range).group(:workspace_id)
                      .pluck(:workspace_id, Arel.sql("COUNT(*)"), Arel.sql("COUNT(*) FILTER (WHERE failed_over_from IS NOT NULL)"), Arel.sql(COST_SQL))
                      .to_h { |id, boxes, failovers, cost| [ id, [ boxes, failovers, cost.to_f.round ] ] }
      workspaces.map { |workspace| Row.new(workspace, *totals.fetch(workspace.id, [ 0, 0, 0 ])) }
    end

    def self.placement_label(key) = key.present? ? SandboxProviders.name_of(key) : following_label

    def self.following_label
      order = [ SandboxProviders.main, SandboxProviders.backup ].compact.uniq.map { |key| SandboxProviders.name_of(key) }
      order.empty? ? "Follow the deployment, which sets none" : "Follow the deployment (#{order.join(', then ')})"
    end

    def initialize(workspace, filter)
      @workspace = workspace
      @filter = filter
    end

    # The provider a choice holds the workspace to, nil for following the deployment.
    def self.key_from(choice) = choice.to_s.strip == FOLLOW_DEPLOYMENT ? nil : choice.to_s.strip.presence

    def placement = @workspace.sandbox_provider.presence || FOLLOW_DEPLOYMENT

    def choices
      [ Choice.new(FOLLOW_DEPLOYMENT, self.class.following_label), *SandboxProviders::KEYS.map { |key| Choice.new(key, SandboxProviders.name_of(key)) } ]
    end

    def failover_count = failed_over.count

    def failovers
      failed_over.order(created_at: :desc).limit(LIMIT).map do |box|
        Failover.new(box.id, box.created_at, SandboxProviders.name_of(box.failed_over_from), SandboxProviders.name_of(box.provider), box.failover_reason.to_s)
      end
    end

    # Each code fix in the window, newest first, with the cost of the boxes its run read and wrote code in while it ran,
    # nil when none of them had a price (a Docker box runs on the deployment's own machines).
    def fixes
      sessions = CodeAgentSession.where(workspace: @workspace, created_at: @filter.range).order(created_at: :desc).limit(LIMIT).to_a
      runs = CodeBox.where(workspace: @workspace, key: sessions.filter_map(&:box_key).uniq).to_a.group_by(&:key)
      sessions.map do |session|
        ran = runs.fetch(session.box_key, []).select { |box| up_during?(box, session) }
        priced = ran.select(&:hourly_micros)
        Fix.new(session.id, session.repository, session.created_at, session.spent_micros, (priced.sum { |box| cost_micros(box) } if priced.any?),
                ran.sum { |box| seconds_run(box) }, ran.map { |box| SandboxProviders.name_of(box.provider) }.uniq, session.pull_request_url)
      end
    end

    def sandbox_micros = self.class.rows(@filter, [ @workspace ]).first.sandbox_micros

    def ai_micros = CodeAgentSession.where(workspace: @workspace, created_at: @filter.range).sum(:spent_micros)

    private

    def failed_over = CodeBox.where(workspace: @workspace, created_at: @filter.range).where.not(failed_over_from: nil)

    # How long a box has run, a box still up counted until now.
    def seconds_run(box)
      return box.running_seconds if box.stopped_at

      box.running_seconds + (Time.current - (box.box_started_at || box.created_at)).to_i.clamp(0..)
    end

    # Its provider's price for its size by the hour, for the time it ran.
    def cost_micros(box) = (box.hourly_micros * seconds_run(box) / 3600.0).round

    def up_during?(box, session)
      ended = session.closed_at || session.expires_at
      box.created_at <= ended && (box.stopped_at.nil? || box.stopped_at >= session.created_at)
    end
  end
end

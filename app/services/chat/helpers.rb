# Runs the checks Halon handed off in one run_helpers call at the same time, each a short agent run with a narrow brief
# and tools that only read, and answers what each reported. A helper reads as whoever the chat or run acts for, so it
# never reaches further than they can, and spends from the same purse the asking loop stops on.
module Chat::Helpers
  # One check as Halon handed it off. deep runs it on the main model rather than the side jobs' one.
  Check = Data.define(:title, :brief, :deep)

  # What the asking turn or run lends its helpers. purse is its loop's (FirefightAi::AgentLoop::Purse) and max_spend_cents
  # the cap that loop stops at. since is when the question began, which the per question limit counts from. canceled
  # says whether a person stopped it, moved is called with the run_helpers call's id whenever one of its helpers moved
  # (see teller), and fresh_parent builds a
  # copy of the asking turn or run for a helper's own thread, since a record is never shared between threads. choose
  # answers the model a check runs on, given whether it is deep, and is asked only once a check is handed off.
  # inferable and member are what the ledger names.
  Share = Data.define(:purse, :max_spend_cents, :since, :canceled, :moved, :fresh_parent, :choose, :inferable, :member)

  # What the asking loop reads, and whether nothing came of it, which marks the call failed.
  Result = Data.define(:text, :failed)

  # One helper as a thread shows it, a line of its own under the step that started it, such as "Logs of checkout" with
  # "2 steps, reported". signature and finished? let a Chat::CodeFixProgress::Pace decide when it is redrawn.
  Line = Data.define(:key, :title, :status, :outcome, :details) do
    def signature = [ status, outcome, details ]

    def finished? = status == FirefightAi::AgentLoop::STEP_DONE
  end

  ENDED_WORDS = {
    Chat::Helper::STATUS_RUNNING => "reading", Chat::Helper::STATUS_REPORTED => "reported",
    Chat::Helper::STATUS_FAILED => "no report", Chat::Helper::STATUS_STOPPED => "stopped"
  }.freeze

  def self.line(helper)
    taken = helper.own_chat ? helper.own_chat.tool_calls.where.not(name: Chat::Tools.internal_names).count : 0
    Line.new(
      key: "#{helper.tool_call_id}-helper-#{helper.position}", title: helper.title,
      status: helper.running? ? FirefightAi::AgentLoop::STEP_RUNNING : FirefightAi::AgentLoop::STEP_DONE,
      outcome: (Chat::StepOutcome::KIND_FAILED if helper.status == Chat::Helper::STATUS_FAILED),
      details: "#{taken == 1 ? '1 step' : "#{taken} steps"}, #{ENDED_WORDS.fetch(helper.status)}"
    )
  end

  # What a share's moved calls, from any helper's thread. The helpers of that call are read again and handed to the
  # delivery, one call at a time, since a delivery speaks to one platform thread in order.
  def self.teller(delivery, chat)
    lock = Mutex.new
    lambda do |tool_call_id|
      lock.synchronize do
        delivery.helpers(key: tool_call_id, helpers: Chat::Helper.where(chat_id: chat.id, tool_call_id: tool_call_id).in_order.includes(:own_chat).to_a)
      end
    rescue StandardError => error
      Rails.logger.warn({ event: "chat_helper.not_told", chat_id: chat.id, error: error.class.name }.to_json)
    end
  end

  # Below this a helper could not pay for a turn on most models, so the loop reads it itself instead.
  MIN_SHARE_CENTS = 1
  NO_BUDGET = "Not enough of this question's budget is left to hand anything off. Read what you still need yourself, or answer with what you have.".freeze
  NO_CHAT = "Helpers need a saved chat to report to, and this one has none.".freeze

  # The side jobs' model, or the main one when the registry knows no context window for it, since a helper makes room
  # from its window like any agent run. deployment is for a rehearsal, which runs on the deployment's account.
  def self.side_model(workspace, main:, deployment: false)
    side = deployment ? FirefightAi.deployment_model_for(AiPurpose::HELPER, workspace: workspace) : FirefightAi.model_for(AiPurpose::HELPER, workspace: workspace)
    FirefightAi.context_window(side.model, provider: side.provider) ? side : main
  end

  # Each helper gets an equal part of what is left, with one more part kept back for the loop that asked, which still
  # has to read the reports and answer.
  def self.run!(agent_run, share:, tool_call_id:, checks:)
    chat = agent_run.chat
    return Result.new(text: NO_CHAT, failed: true) unless chat

    cents = (share.purse.left(share.max_spend_cents) / (checks.size + 1)) / FirefightAi::AgentLoop::MICROS_PER_CENT
    return Result.new(text: NO_BUDGET, failed: true) if cents < MIN_SHARE_CENTS

    started = Chat::Helper.start!(chat: chat, tool_call_id: tool_call_id, checks: checks, since: share.since)
    return Result.new(text: started, failed: true) if started.is_a?(String)

    share.moved.call(tool_call_id)
    # Chosen here, before any thread starts, since choosing reads the workspace's accounts.
    models = started.map(&:deep).uniq.index_with { |deep| share.choose.call(deep) }
    run_together(started, share: share, max_spend_cents: cents, models: models)
    started.each(&:reload)
    share.moved.call(tool_call_id)
    Result.new(text: reports(started), failed: started.none?(&:reported?))
  end

  # Helper threads one worker process runs at once. Each can hold a database connection while it works, and the pool is
  # sized for the worker's own threads plus a few, so past this a helper waits for another to finish rather than for a
  # connection it might never get.
  THREADS_PER_PROCESS = 6
  SLOTS = Concurrent::Semaphore.new(THREADS_PER_PROCESS)

  # Every helper on a thread of its own, and the asking loop waits for all of them. A helper that fails ends with a
  # sentence and never takes the others down with it.
  def self.run_together(helpers, share:, max_spend_cents:, models:)
    threads = helpers.map do |helper|
      Thread.new do
        SLOTS.acquire
        begin
          Rails.application.executor.wrap do
            Chat::Helpers::Run.new(helper, share: share, max_spend_cents: max_spend_cents, choice: models.fetch(helper.deep)).call
          end
        ensure
          SLOTS.release
        end
      end
    end
    ActiveSupport::Dependencies.interlock.permit_concurrent_loads { threads.each(&:join) }
  end

  # What the asking loop reads back, one helper a line, in the order they were handed off.
  def self.reports(helpers)
    done = helpers.count(&:reported?)
    [ "Helpers reported, #{done} of #{helpers.size}:", *helpers.map(&:line) ].join("\n")
  end
end

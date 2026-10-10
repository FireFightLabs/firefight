# The chat bench: Halon replayed on scenarios written from real failures, or on one real chat, and scored on whether it
# was right, moved the work forward, asked only when it needed to, and what it cost. Every replay answers from a
# record, so a change to Halon's prompt, tools or loop is what moves the score.
class Conversation::Bench
  NO_ANSWER = "The replay ended without a reply.".freeze
  LOST = "The replay stopped without finishing, so its worker was lost.".freeze
  OUT_OF_CREDIT = "The replay could not finish, since the AI account is out of credit.".freeze
  # Said on the run and on each scenario it never reached, once the account a run pays with refuses it.
  ACCOUNT_REFUSED = "The run stopped, since the AI account it pays with refused it (out of credit, or the key was refused). " \
                    "Nothing more was replayed or judged.".freeze

  # The scenarios have no customer behind them, so they run in a workspace of their own that nobody belongs to. It is
  # the one the bench made for its first run, found again through the scenarios that ran there.
  WORKSPACE_NAME = "Halon bench".freeze
  WORKSPACE_LOCK = 7_210_051

  # Replays that run at once from the terminal, each a whole chat on the model. Each holds a database connection, and the
  # terminal gives a run a pool of this many plus one.
  AT_ONCE = 3

  # Refuses a run while too many are going, since every run holds database connections on a server others share.
  class Busy < StandardError; end

  class << self
    # Queues every scenario for the workers. Used by the console.
    def start!(trigger:, model: nil, provider: nil, by: nil, label: nil)
      run = create_run!(trigger: trigger, model: model, provider: provider, by: by, label: label)
      run.results.each { |result| HalonBenchCaseJob.perform_later(result.id) }
      run
    end

    # Runs every scenario here and now, a few at a time, for the terminal and CI. keys picks some by name.
    def run!(trigger:, model: nil, provider: nil, label: nil, keys: nil, &reported)
      run = create_run!(trigger: trigger, model: model, provider: provider, label: label, keys: keys)
      queue = Queue.new
      run.results.each { |result| queue << result.id }
      queue.close
      Array.new([ AT_ONCE, run.results.size ].min) do
        Thread.new do
          Rails.application.executor.wrap do
            while (id = queue.pop)
              result = Conversation::BenchResult.find(id)
              run_case!(result)
              reported&.call(result.reload)
            end
          end
        end
      end.each(&:join)
      run.reload
    end

    # One real chat, replayed in its own workspace from its record. Its right outcome was never written down, so that
    # part is not scored.
    def replay_chat!(conversation, trigger:, model: nil, provider: nil, label: nil)
      busy = Conversation::BenchRun.busy_reason
      raise Busy, busy if busy

      choice = model_choice(model, provider)
      run = Conversation::BenchRun.transaction do
        Conversation::BenchRun.create!(
          kind: Conversation::BenchRun::KIND_CHAT, trigger: trigger, prompt_version: prompt_version(conversation.workspace, choice),
          model: choice.model, provider: choice.provider, label: label
        ).tap do |created|
          created.results.create!(workspace: conversation.workspace, replay_of: conversation, scenario: "chat-#{conversation.id}", title: conversation.display_title)
        end
      end
      run_case!(run.results.sole)
      run.reload
    end

    def run_case!(result)
      return unless result.claim!
      return result.settle!(status: Conversation::BenchResult::STATUS_ERRORED, reason: ACCOUNT_REFUSED) if result.bench_run.reload.stopped?

      score(result)
    rescue StandardError => error
      Rails.logger.warn({ event: "halon_bench.case_errored", result_id: result.id, error: error.class.name }.to_json)
      refused = account_refused?(error)
      result.bench_run.stop!(ACCOUNT_REFUSED) if refused
      reason = refused ? ACCOUNT_REFUSED : "The replay could not finish (#{error.class.name})."
      result.settle!(status: Conversation::BenchResult::STATUS_ERRORED, reason: reason, spent_micros: spent(result))
    ensure
      result.bench_run.finish_if_done!
    end

    # The account refused the run rather than one call: out of credit, or its key refused. Every later call would be
    # refused the same way, so the run stops.
    def account_refused?(error)
      [ error, error.cause ].compact.any? do |raised|
        AiCredit.out?(raised) || AiPayer.gives_way?(raised) || raised.is_a?(RubyLLM::PaymentRequiredError) ||
          (raised.is_a?(FirefightAi::Error) && raised.reason == RubyLLM::PaymentRequiredError.name.demodulize)
      end
    end

    # A scenario whose worker died is settled, so its run can finish.
    def settle_stale!
      Conversation::BenchResult.stale.includes(:bench_run).find_each { |result| settle_lost!(result) }
    end

    # Also when the same job comes back after its worker was stopped mid replay, since the claim keeps it from running twice.
    def settle_lost!(result)
      result.settle!(status: Conversation::BenchResult::STATUS_ERRORED, reason: LOST, spent_micros: spent(result))
      result.bench_run.finish_if_done!
    end

    # The bench runs on its own key, never the app's or a workspace's (Conversation::BenchKeys), so a score says how Halon
    # did and a run can never spend what live chats run on. Nil model means the model Halon runs on by default.
    def model_choice(model, provider)
      return Conversation::BenchKeys.choice(model: model, provider: provider) if model.present?

      deployed = FirefightAi.deployment_model_for(AiPurpose::INVESTIGATION)
      Conversation::BenchKeys.choice(model: deployed.model, provider: deployed.provider_name)
    end

    # Made in the same transaction as the run that first needs it, so a run that fails to start leaves no workspace.
    def workspace
      Workspace.transaction do
        Workspace.connection.execute("SELECT pg_advisory_xact_lock(#{WORKSPACE_LOCK})")
        used = Conversation::BenchResult.joins(:bench_run).merge(Conversation::BenchRun.of_scenarios).pick(:workspace_id)
        (used && Workspace.find_by(id: used)) || Workspace.create!(name: WORKSPACE_NAME)
      end
    end

    private

    def create_run!(trigger:, model:, provider:, label:, by: nil, keys: nil)
      busy = Conversation::BenchRun.busy_reason
      raise Busy, busy if busy

      scenarios = Conversation::BenchCase.scenarios
      scenarios = scenarios.select { |scenario| keys.include?(scenario.key) } if keys.present?
      raise Conversation::BenchCase::Invalid, "No scenario is called #{(keys - scenarios.map(&:key)).to_sentence}." if keys.present? && scenarios.size < keys.size

      choice = model_choice(model, provider)
      Conversation::BenchRun.transaction do
        bench = workspace
        Conversation::BenchRun.create!(
          kind: Conversation::BenchRun::KIND_SCENARIOS, trigger: trigger, prompt_version: prompt_version(bench, choice),
          model: choice.model, provider: choice.provider, label: label, started_by: by
        ).tap do |run|
          scenarios.each { |scenario| run.results.create!(workspace: bench, scenario: scenario.key, title: scenario.title) }
        end
      end
    end

    def prompt_version(workspace, choice) = FirefightAi::Responder.new(workspace, inferable: nil, model: choice).prompt_version

    # What Halon's own model calls cost, from the inference ledger. The judge's call is grading, so it is left out.
    def spent(result) = Inference.where(inferable: result, feature: FirefightAi::Responder::FEATURE).sum(:cost_micros)

    def case_for(result)
      result.replay_of ? Conversation::Rehearsal.capture(result.replay_of) : Conversation::BenchCase.scenario(result.scenario)
    end

    def score(result)
      bench_case = case_for(result)
      run = result.bench_run
      replay = Conversation::Rehearsal.replay!(bench_case, result: result, model: model_choice(run.model, run.provider))
      transcript = replay.transcript
      halon_spent = spent(result)
      columns = { spent_micros: halon_spent, turns: replay.turns_used, calls: transcript.calls.size, not_recorded: transcript.not_recorded,
                  confirmations: transcript.confirmations.size }
      # A turn that ended on a confirmation stopped to ask, which is scored. Only a chat that said nothing at all is not.
      if transcript.replies.empty? && transcript.waiting.empty?
        return result.settle!(status: Conversation::BenchResult::STATUS_ERRORED, reason: NO_ANSWER, **columns)
      end

      verdict = FirefightAi::ReplayJudge.new(result.workspace, inferable: result, model: Conversation::BenchKeys.judge)
                                        .judge(transcript: transcript.to_text, outcome: bench_case.expect.outcome, next_step: bench_case.expect.next_step)
      scored = Conversation::BenchScore.of(transcript: transcript, verdict: verdict, expect: bench_case.expect, spent_micros: halon_spent)
      result.settle!(
        status: Conversation::BenchResult::STATUS_SCORED, **scored.to_h, total: scored.total, **columns,
        unneeded_asks: transcript.unneeded_confirmations.size + verdict.unneeded_questions,
        answer: transcript.answer, reason: verdict.reason,
        notes: Conversation::BenchScore.notes(transcript: transcript, verdict: verdict, expect: bench_case.expect)
      )
    end
  end
end

# Runs an investigation where nobody in the workspace sees it, to measure Halon. A replay answers every tool call from a
# finished run's record, on the same or another model, so only the reasoning differs. A bench run reads live systems for
# an incident whose cause is known, and is scored on whether its finding names it. Neither posts, holds the incident's
# live run, or becomes a past answer.
class Investigation::Rehearsal
  HOLDER = "rehearsal".freeze

  Result = Data.define(:investigation, :model, :status, :summary, :cause, :claims, :turns, :spent_cents, :steps, :not_recorded, :seconds) do
    # Every expected text appears in what the finding says, whatever its case.
    def names?(expected)
      said = [ summary, cause, *claims ].join("\n").downcase
      Array(expected).all? { |text| said.include?(text.to_s.downcase) }
    end
  end

  class << self
    def replay!(original, model: nil, provider: nil)
      run = rehearse!(
        original.subject, replay_of: original, seed_pack: original.seed_pack, brief: original.brief,
        max_turns: original.max_turns, max_spend_cents: original.max_spend_cents, model: model, provider: provider
      )
      copy_steps_before_the_loop(original, run)
      finish(run)
    end

    # said is what the person would have typed, which the run reads as its brief.
    def bench!(incident, said:, model: nil, provider: nil)
      limits = incident.workspace.investigation_limits
      brief = Investigation::Brief.from({ Investigation::Brief::KEY_SYMPTOM => said }, source: Investigation::Brief::SOURCE_REHEARSAL)
      run = rehearse!(
        incident, brief: brief, max_turns: limits.max_turns, max_spend_cents: limits.max_spend_cents, model: model, provider: provider
      )
      run.build_seed_pack!
      Investigation::WhatChanged.new(run).note!
      finish(run)
    end

    def summarize(run)
      finding = run.finding
      Result.new(
        investigation: run, model: run.chat&.model_id, status: run.status, summary: finding&.summary,
        cause: finding&.winning_hypothesis&.assertion, claims: finding ? finding.evidence_items.map(&:claim) : [],
        turns: run.turns_used, spent_cents: (run.spent_micros / FirefightAi::AgentLoop::MICROS_PER_CENT.to_f).round(2),
        steps: run.steps.count, not_recorded: run.steps.where(error_summary: Investigation::ToolCall::NOT_RECORDED).count,
        seconds: run.started_at && run.completed_at ? (run.completed_at - run.started_at).round : nil
      )
    end

    private

    def rehearse!(subject, model:, provider:, **attributes)
      subject.workspace.investigations.create!(
        subject: subject, trigger_source: Investigation::TRIGGER_REHEARSAL, rehearsal: true,
        model_override: model.presence, provider_override: provider.presence, **attributes
      )
    end

    # What happened before the loop, such as what changed before the trouble, is already in the facts the replay starts
    # from, with step numbers its evidence may cite. Those steps come across as they were.
    def copy_steps_before_the_loop(original, run)
      opened = original.chat&.created_at
      return unless opened

      original.steps.where(investigation_steps: { created_at: ...opened }).each do |step|
        run.steps.create!(step.attributes.slice(
          "position", "tool_name", "label", "action_key", "params", "status", "error_summary",
          "compacted_result", "raw_result", "started_at", "completed_at"
        ))
      end
    end

    def finish(run)
      run.claim!(by: HOLDER)
      result = Investigation::Runner.new(run).run
      run.finish!(status: result.status, error_summary: result.error_summary)
      summarize(run.reload)
    rescue StandardError => error
      run.finish!(status: Investigation::STATUS_FAILED, error_summary: error.class.name)
      raise
    ensure
      Integrations::CodeReading.close(run.code_box_key)
    end
  end
end

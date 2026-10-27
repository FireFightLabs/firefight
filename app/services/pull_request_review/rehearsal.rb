# A pull request review run to measure Halon, such as the comparison with another reviewer: at any commit of the pull
# request, against any base, on the model being compared, paid with the bench's own key (Conversation::BenchKeys), and
# capped at what it may spend. It runs here and now rather than on a worker, nobody in the workspace sees it, nothing is
# announced or posted, and its findings never count as problems prevented. The result is the review with its findings,
# and to_h gives them as data to score.
class PullRequestReview::Rehearsal
  # A runner that is not a job holds the review under this name.
  HOLDER = "rehearsal".freeze

  # head_sha and base_sha pin the commits to review, such as one round of another reviewer's, and default to the pull
  # request as its code host shows it now.
  def self.run!(workspace:, repository:, number:, max_spend_cents:, head_sha: nil, base_sha: nil, model: nil, provider: nil)
    row = Integrations::ReviewHost.row_for(workspace, repository)
    raise PullRequestReview::Start::Refused, format(PullRequestReview::Start::NOT_HELD, repository: repository) unless row

    pull = PullRequestReview.reading!(row, repository: repository, number: number) do
      Integrations::ReviewHost.pull_request(row, repository: repository, number: number)
    end
    review = PullRequestReview.create!(
      workspace: workspace, integration_environment: row, repository: repository, number: number, head_sha: head_sha.presence || pull.head_sha,
      base_sha: base_sha.presence, trigger: PullRequestReview::TRIGGER_REQUESTED, rehearsal: true, max_spend_cents: max_spend_cents,
      model_override: model.presence, provider_override: provider.presence
    )
    run(review)
  end

  def self.run(review)
    review.claim!(by: HOLDER)
    result = PullRequestReview::Runner.new(review, by: HOLDER).run
    review.finish!(status: result.status, error_summary: result.error_summary)
    review
  rescue StandardError => error
    review.finish!(status: PullRequestReview::STATUS_FAILED, error_summary: PullRequestReviewJob.stopped_because(error))
    Rails.logger.warn({ event: "pull_request_review.rehearsal_failed", pull_request_review_id: review.id, error: "#{error.class.name}: #{error.message}" }.to_json)
    review
  ensure
    Integrations::CodeReading.close(review.code_box_key)
  end

  # The review as data to score: what it read, its summary and risk, every finding with its labels and chain, and the
  # findings its checks dropped with why.
  def self.to_h(review)
    review.reload
    {
      "review" => review.id, "repository" => review.repository, "number" => review.number, "head_sha" => review.head_sha, "base_sha" => review.base_sha,
      "status" => review.status, "error" => review.error_summary, "model" => review.model, "provider" => review.provider,
      "spent_cents" => review.spent_cents, "turns" => review.turns_used, "risk" => review.risk, "risk_reason" => review.risk_reason,
      "summary" => review.summary, "reviewed" => review.reviewed_paths, "left_out" => review.left_out,
      "findings" => review.findings.map { |finding| finding_h(finding) },
      "dropped" => review.checks.where(verdict: [ PullRequestReview::Check::VERDICT_DROPPED, nil ]).map { |check| { "claim" => check.claim, "path" => check.path, "reason" => check.reason } }
    }
  end

  def self.finding_h(finding)
    finding.slice(:position, :status, :category, :severity, :effort, :serious, :path, :line, :outside_diff, :claim, :why, :failure_chain, :evidence,
                  :checks, :cross_checks, :suggested_fix, :agent_instructions, :withdrawn_reason).stringify_keys
  end

  private_class_method :finding_h
end

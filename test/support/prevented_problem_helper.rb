# A pull request Halon reviewed and a finding on it, fixed and merged as asked, for the count of problems prevented.
module PreventedProblemHelper
  def reviewed_pull_request!(workspace, number:, merged_at:, rehearsal: false)
    workspace.pull_request_reviews.create!(
      repository: "acme/checkout", number: number, title: "Shorten the payment timeout", url: "https://github.com/acme/checkout/pull/#{number}",
      head_sha: "b" * 40, trigger: PullRequestReview::TRIGGER_AUTOMATIC, status: PullRequestReview::STATUS_DONE, max_spend_cents: 400,
      rehearsal: rehearsal, merged_at: merged_at
    )
  end

  def review_finding!(review, claim: "Keep the payment timeout above the gateway's", severity: PullRequestReview::Finding::SEVERITY_MAJOR,
                      serious: false, fixed_at: nil, position: review.next_position)
    review.findings.create!(
      position: position, fingerprint: SecureRandom.hex(16), category: PullRequestReview::Finding::CATEGORY_STABILITY, severity: severity,
      effort: PullRequestReview::Finding::EFFORT_QUICK_WIN, claim: claim, why: "The gateway waits 30 seconds, so a 10 second timeout retries a payment still in flight.",
      failure_chain: [ "The timeout drops to 10 seconds", "Checkout retries payments the gateway is still taking", "Customers are charged twice, as in INC-012" ],
      evidence: [ { "kind" => PullRequestReview::Finding::EVIDENCE_INCIDENT, "title" => "INC-012 Double charges at checkout", "url" => "https://app.example.com/incidents/12" },
                  { "kind" => PullRequestReview::Finding::EVIDENCE_CODE, "title" => "config/payments.yml", "url" => nil } ],
      path: "config/payments.yml", line: 4, serious: serious, host_comment_id: "4253331341",
      host_comment_url: "https://github.com/acme/checkout/pull/#{review.number}#discussion_r4253331341"
    ).tap { |finding| finding.update_columns(status: PullRequestReview::Finding::STATUS_FIXED, fixed_in_sha: "1cb47a9" + ("0" * 33), fixed_at: fixed_at) if fixed_at }
  end
end

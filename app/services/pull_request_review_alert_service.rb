# A pull request Halon reviewed as high risk is also posted in the channel of each service that owns its repository,
# unless the service turned it off, falling back to an owning team's channel. Posted once per pull request, however
# many times it is reviewed again.
class PullRequestReviewAlertService
  # What the platform message shows, so the adapter never reads a review record. findings are the open ones, the most
  # severe first.
  Shown = Data.define(:repository, :number, :title, :url, :risk_reason, :service, :findings)
  ShownFinding = Data.define(:severity, :claim, :lesson)

  def initialize(review)
    @review = review
  end

  # Returns the channels it posted in. A channel that cannot take it, such as one archived or without the app, is
  # skipped, and the others still get it.
  def post!
    return [] unless due?

    destinations = @review.owning_services.filter_map { |service| [ service.review_alert_channel, service ] if service.review_alert_channel }
                          .uniq(&:first)
    return [] if destinations.empty? || !claim!

    destinations.filter_map do |channel_id, service|
      @review.workspace.adapter.post_high_risk_pull_request(channel_id: channel_id, alert: shown(service))
      channel_id
    rescue AdapterError => error
      Rails.logger.info({ event: "pull_request_review.high_risk_not_posted", review_id: @review.id, error: error.class.name }.to_json)
      nil
    end
  end

  private

  def due?
    return false if @review.rehearsal? || !@review.done? || @review.risk != PullRequestReview::RISK_HIGH

    !PullRequestReview.seen.of_pull_request(@review.repository, @review.number).where(workspace: @review.workspace)
                      .where.not(high_risk_posted_at: nil).exists?
  end

  # Guarded, so two workers finishing the same review post once.
  def claim!
    PullRequestReview.where(id: @review.id, high_risk_posted_at: nil).update_all(high_risk_posted_at: Time.current, updated_at: Time.current) > 0
  end

  def shown(service)
    findings = @review.findings.open.preload(lesson: :source).to_a
                      .sort_by { |finding| [ PullRequestReview::Finding::SEVERITIES.index(finding.severity), finding.position ] }
    Shown.new(repository: @review.repository, number: @review.number, title: @review.title.to_s, url: @review.url,
              risk_reason: @review.risk_reason, service: service.name,
              findings: findings.map { |finding| ShownFinding.new(severity: finding.severity_label, claim: finding.claim, lesson: finding.lesson_label) })
  end
end

# A pull request Halon reviewed as high risk is also posted in the channel of each service that owns its repository,
# unless the service turned it off, falling back to an owning team's channel. Posted once per pull request, however
# many times it is reviewed again.
class PullRequestReviewAlertService
  # What the platform message shows, so the adapter never reads a review record. findings are the open ones, the most
  # severe first.
  Shown = Data.define(:repository, :number, :title, :url, :risk_reason, :service, :findings)
  ShownFinding = Data.define(:severity, :claim, :lesson)

  # A failure worth trying again, such as Slack limiting the rate, raised once every other channel was tried so the job
  # retries only what is left.
  class Retry < StandardError; end
  RETRYABLE = [ AdapterError::RateLimited, AdapterError::ServerError, AdapterError::Unavailable ].freeze

  def initialize(review)
    @review = review
  end

  # Returns the channels it posted in. A channel that cannot take it, such as one archived or without the app, is
  # skipped, and the others still get it. A channel posted in already is never posted in again on a retry.
  def post!
    return [] unless due?

    destinations = @review.owning_services.filter_map { |service| [ service.review_alert_channel, service ] if service.review_alert_channel }
                          .uniq(&:first)
    return [] if destinations.empty? || !claim!

    again = []
    posted = destinations.filter_map do |channel_id, service|
      next if @review.high_risk_posted_channels.include?(channel_id)

      @review.workspace.adapter.post_high_risk_pull_request(channel_id: channel_id, alert: shown(service))
      delivered!(channel_id)
      channel_id
    rescue *RETRYABLE => error
      again << channel_id
      not_posted(error)
    rescue AdapterError => error
      not_posted(error)
    end
    raise Retry, "#{again.size} #{'channel'.pluralize(again.size)} to try again" if again.any?

    posted
  end

  private

  # Done, high risk and seen, and not posted for an earlier review of the same pull request.
  def due?
    return false if @review.rehearsal? || !@review.done? || @review.risk != PullRequestReview::RISK_HIGH

    !PullRequestReview.seen.of_pull_request(@review.repository, @review.number).where(workspace: @review.workspace)
                      .where.not(id: @review.id).where.not(high_risk_posted_at: nil).exists?
  end

  # Takes the pull request's one post for this review, or finds it taken by this review already, as on a retry.
  def claim!
    taken = PullRequestReview.where(id: @review.id, high_risk_posted_at: nil).update_all(high_risk_posted_at: Time.current, updated_at: Time.current) > 0
    @review.reload
    taken || @review.high_risk_posted_at.present?
  end

  def delivered!(channel_id)
    PullRequestReview.where(id: @review.id)
                     .update_all([ "high_risk_posted_channels = high_risk_posted_channels || ?::jsonb, updated_at = ?", [ channel_id ].to_json, Time.current ])
    @review.reload
  end

  def not_posted(error)
    Rails.logger.info({ event: "pull_request_review.high_risk_not_posted", review_id: @review.id, error: error.class.name }.to_json)
    nil
  end

  def shown(service)
    findings = @review.findings.still_open.preload(lesson: :source).to_a
                      .sort_by { |finding| [ PullRequestReview::Finding::SEVERITIES.index(finding.severity), finding.position ] }
    Shown.new(repository: @review.repository, number: @review.number, title: @review.title.to_s, url: @review.url,
              risk_reason: @review.risk_reason, service: service.name,
              findings: findings.map { |finding| ShownFinding.new(severity: finding.severity_label, claim: finding.claim, lesson: finding.lesson_label) })
  end
end

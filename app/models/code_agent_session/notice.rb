# What Halon told about a pull request it opened: the problems the code host showed (a conflict with its base, failing
# checks, a reviewer asking for changes) on one head, with Fix it. One per set of problems on the same commits, which a
# unique index holds, so a live update and the sweep arriving together say it once. Fix it is the only yes: nothing on
# the branch changes until the person the change runs as presses it, and then it runs as them through the gateway.
class CodeAgentSession::Notice < ApplicationRecord
  STATUS_OFFERED = "offered"
  # Fix it was pressed, and the code change runs as the person who asked in their chat.
  STATUS_FIXING = "fixing"
  # A later read found the problems gone, or other ones, or the pull request ended, before anyone pressed Fix it.
  STATUS_CLEARED = "cleared"
  STATUS_REPLACED = "replaced"
  STATUS_ENDED = "ended"
  STATUSES = [ STATUS_OFFERED, STATUS_FIXING, STATUS_CLEARED, STATUS_REPLACED, STATUS_ENDED ].freeze
  DETAIL_LIMIT = 600

  belongs_to :session, class_name: "CodeAgentSession", inverse_of: :notices
  belongs_to :workspace
  belongs_to :fix_by, class_name: "WorkspaceMembership", optional: true
  # The chat it was told in, where Fix it runs. A fix's notice in a run's thread has none until Fix it opens the thread's.
  belongs_to :conversation, optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :offered, -> { where(status: STATUS_OFFERED) }
  scope :untold, -> { where(told_at: nil) }

  # Kept once for these problems, or nil when it was already said.
  def self.record!(session, status)
    create!(session_id: session.id, workspace_id: session.workspace_id, fingerprint: status.fingerprint, head_sha: status.head_sha, base: status.base,
            status: STATUS_OFFERED, problems: problems_of(status))
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def self.problems_of(status)
    status.problems.map do |problem|
      detail = case problem
      when Integrations::PullRequests::PROBLEM_CONFLICT then nil
      when Integrations::PullRequests::PROBLEM_CHECKS then status.failing_checks.map(&:name).join(", ")
      else status.reviews.map { |review| [ review.reviewer, review.body.squish.presence ].compact.join(": ") }.join(" / ")
      end
      { "kind" => problem, "detail" => detail.to_s.truncate(DETAIL_LIMIT).presence }.compact
    end
  end

  def offered? = status == STATUS_OFFERED

  def kinds = problems.map { |problem| problem["kind"] }

  # The reason in a sentence, as Halon and a notification read it, naming the pull request.
  def reason = "#{session.pull_request_label} needs attention: #{causes.to_sentence}."

  # The same under the headline that already names it.
  def why = "#{causes.to_sentence.upcase_first}."

  def causes
    problems.map do |problem|
      case problem["kind"]
      when Integrations::PullRequests::PROBLEM_CONFLICT then "it conflicts with #{base} now"
      when Integrations::PullRequests::PROBLEM_CHECKS then "#{problem['detail'].to_s.include?(',') ? 'checks' : 'a check'} failed (#{problem['detail']})"
      else "a reviewer asked for changes (#{problem['detail']})"
      end
    end
  end

  def headline = "#{session.pull_request_label} needs attention"

  # What Fix it does, in the person's words, so they know what they are agreeing to.
  def offer
    steps = []
    steps << "merge #{base} in and resolve the conflict" if kinds.include?(Integrations::PullRequests::PROBLEM_CONFLICT)
    steps << "fix what makes the failing checks fail" if kinds.include?(Integrations::PullRequests::PROBLEM_CHECKS)
    steps << "make the changes the reviewer asked for" if kinds.include?(Integrations::PullRequests::PROBLEM_REVIEW)
    "Fix it has Halon #{steps.to_sentence} on the pull request's branch, as #{session.principal.try(:display_name) || 'the person who asked'}. Nothing changes until it is pressed."
  end

  # Fix it runs as whoever asked for the change, so only they can press it.
  def fix_blocked_reason(member)
    return "This was already taken care of." unless offered?
    return "#{session.pull_request_label} is no longer open." unless session.following?
    return "Only #{session.principal.try(:display_name) || 'the person who asked'} can press Fix it, since the change runs as them." unless member && session.principal == member

    nil
  end

  # Fix it pressed, once. False when someone pressed it first or a later read moved it on.
  def claim_fix!(member)
    moved = self.class.where(id: id, status: STATUS_OFFERED).update_all(status: STATUS_FIXING, fix_by_id: member.id, fix_at: Time.current, updated_at: Time.current)
    reload
    moved == 1
  end

  # A later read moved on from it before anyone pressed Fix it.
  def self.settle_offered!(session, status_to, except: nil)
    offered = session.notices.offered.where.not(id: except&.id).to_a
    where(id: offered.map(&:id), status: STATUS_OFFERED).update_all(status: status_to, updated_at: Time.current)
    offered.map(&:reload)
  end
end

# What a step that went through produced, as a link a person can follow: the pull request a code change opened, or the
# first address the tool's answer gave, such as a deploy or a rollback on the provider's own page. Read from the step's
# own result, so every tool that answers with an address gets a link without code of its own.
module Investigation::RemediationStep::Outcome
  PULL_REQUEST = %r{https?://[^\s<>|()"']+?/(?:pull|pulls|merge_requests|pull-requests)/(\d+)}
  ADDRESS = %r{https?://[^\s<>|()"'`\]]+}
  LABEL_LIMIT = 60

  module_function

  # [label, url] or nil. A coding agent's own record of the pull request comes first, then what the answer says.
  def of(result, work)
    url = work&.pull_request.presence || result.to_s[PULL_REQUEST] || result.to_s[ADDRESS]&.sub(/[.,;:!?]+\z/, "")
    return nil if url.blank?

    number = url[PULL_REQUEST, 1]
    [ number ? "PR ##{number}" : label(url), url ]
  end

  # The words before the link, by what the step was and what the link is.
  def lead(step)
    return "Link" if step.outcome_url.blank?
    return "Pull request" unless step.outcome_url.match?(PULL_REQUEST)
    return "Pull request" unless step.pull_request?

    step.work&.outcome == Chat::CodeFixProgress::OUTCOME_PUSHED ? "Updated the pull request" : "Opened a pull request"
  end

  # An address without its scheme, cut to what a line holds.
  def label(url) = url.sub(%r{\Ahttps?://}, "").delete_suffix("/").truncate(LABEL_LIMIT)
end

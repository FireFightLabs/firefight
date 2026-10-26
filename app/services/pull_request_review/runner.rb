# One review of a pull request, from reading it on its code host to its summary. The head is checked out in the review's
# sandbox, every changed file is read, and the diff is reviewed in parts on one chat so every file is covered however
# large the pull request is. Each finding the reviewer reports is checked on its own (PullRequestReview::Verification)
# and written the moment it holds, so whatever shows the review catches up as it goes. Every model call is in the
# inference ledger against the review, and what it spends is kept on it. Nothing here posts to the code host.
class PullRequestReview::Runner
  # Another worker took the review over, so this one stops where it is.
  class LeaseLost < StandardError; end

  Result = Data.define(:status, :error_summary)

  # Files are read in this order, what most often breaks production first. Dependency lockfiles, tests and docs come
  # last, so a spending limit that runs out leaves out what matters least.
  KIND_ORDER = [
    CodeChange::KIND_MIGRATION, CodeChange::KIND_CONFIG, CodeChange::KIND_FEATURE_FLAG, CodeChange::KIND_INFRASTRUCTURE, CodeChange::KIND_CODE,
    CodeChange::KIND_DEPENDENCY, CodeChange::KIND_TEST, CodeChange::KIND_DOCS
  ].freeze
  # Why a file the review never reached is left out, as its summary says it.
  BUDGET_SPENT = "the review's spending limit ran out before it finished reading it".freeze
  OUT_OF_STEPS = "the review ran out of steps before it finished reading it".freeze
  # The lease is renewed at most this often, while the loop looks for a stop every second.
  RENEW_EVERY = 30.seconds
  # What the check of a finding reads of the file's diff.
  CHECK_DIFF_LIMIT = 20_000

  attr_reader :review, :purse

  def initialize(review, by:)
    @review = review
    @by = by
    @purse = FirefightAi::AgentLoop::Purse.new(review.spent_micros)
  end

  def run
    row = review.integration_environment
    return Result.new(status: PullRequestReview::STATUS_FAILED, error_summary: PullRequestReview::NO_CONNECTION) unless row

    @row = row
    read_pull_request!
    review_parts!
    conclude!
    Result.new(status: PullRequestReview::STATUS_DONE, error_summary: nil)
  end

  # The model every call of the review runs on. A rehearsal pays with the bench's own key, never the workspace's.
  def choice
    @choice ||= if review.rehearsal?
      model = review.model_override.presence || FirefightAi.deployment_model_for(AiPurpose::CODE_REVIEW).model
      provider = review.model_override.present? ? review.provider_override : FirefightAi.deployment_model_for(AiPurpose::CODE_REVIEW).provider_name
      Conversation::BenchKeys.choice(model: model, provider: provider)
    else
      FirefightAi.model_for(AiPurpose::CODE_REVIEW, workspace: review.workspace)
    end
  end

  def verifier = @verifier ||= FirefightAi::FindingVerifier.new(review.workspace, inferable: review, choice: choice)

  # Asked between steps. Renews the lease now and then, and says stop once another worker holds the review.
  def canceled
    lambda do
      now = Time.current
      return false if @renewed_at && now - @renewed_at < RENEW_EVERY

      @renewed_at = now
      !review.renew_lease!(by: @by)
    end
  end

  # What the reviewer is told about one report: refused with why, or what its check did.
  def report(arguments)
    proposal, refusal = PullRequestReview::Proposal.read(arguments, self)
    return refusal if refusal

    PullRequestReview::Verification.new(self, proposal).run
  end

  # A path at the head, or one the pull request removed.
  def known_path?(path) = path.present? && (@checkout.holds?(path) || @patches.key?(path))

  # A line a comment cannot sit on, since no hunk of the file's diff holds it, or a file the pull request did not change.
  def outside_diff?(path, line)
    return true unless @patches.key?(path)
    return false if line.nil?

    Integrations::ReviewHost.commentable_lines(@patches[path]).none? { |range| range.cover?(line) }
  end

  def file_link(path, line)
    Integrations::ReviewHost.file_link(@row, repository: @checkout.repository, sha: @checkout.ref, path: path, line: line)
  end

  def incident_link(identifier)
    incident = incident_named(identifier)
    incident && AppUrl.absolute(url_helpers.incident_path(incident))
  end

  def postmortem_link(identifier)
    incident = incident_named(identifier)
    incident&.postmortem && AppUrl.absolute(url_helpers.incident_postmortem_path(incident))
  end

  def resource_link(id)
    return unless id.to_s.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)

    resource = ResourceMap::Resource.visible_to(agent_principal, review.workspace).present.find_by(id: id)
    resource && AppUrl.absolute(url_helpers.resource_map_path(ResourceMap::PAGE_VIEW_PARAM => ResourceMap::VIEW_FOCUS, ResourceMap::PAGE_RESOURCE_PARAM => resource.id))
  end

  # Whether a result the review read holds the text, such as a metric's link, in its own chat or a check's. Results are
  # encrypted, so they are read rather than searched.
  def read?(text)
    chats = Chat.where(owner: review).or(Chat.where(owner_type: PullRequestReview::Check.name, owner_id: review.checks.select(:id))).select(:id)
    Chat::Message.where(chat_id: chats, role: Chat::Message::ROLE_TOOL).find_each.any? { |message| message.content.to_s.include?(text) } ||
      Chat::SavedResult.where(chat_id: chats).find_each.any? { |saved| saved.content.to_s.include?(text) }
  end

  # What a check of a finding on path needs about the pull request.
  def check_context(path)
    diff = @patches[path]
    [
      "#{review.repository} PR ##{review.number}: #{review.title}",
      "The head is #{@checkout.ref} in #{@checkout.repository}, and the base is #{review.base_sha}. Read the code with those as the ref.",
      (diff ? "The pull request's diff of #{path}:\n#{FirefightAi::Evidence.frame('pull_request_diff', diff.truncate(CHECK_DIFF_LIMIT))}" : "The pull request does not change #{path}.")
    ].join("\n\n")
  end

  private

  def read_pull_request!
    pull = Integrations::ReviewHost.pull_request(@row, repository: review.repository, number: review.number)
    base_sha = review.base_sha.presence || pull.base_sha
    at_head = pull.with(head_sha: review.head_sha)
    review.update!(title: pull.title, url: pull.url, base_ref: pull.base_ref, head_ref: pull.head_ref, base_sha: base_sha, model: choice.model,
                   provider: choice.provider_name, merged_at: review.merged_at || pull.merged_at)
    @pull = pull
    @checkout = Integrations::ReviewHost.checkout!(@row, at_head, key: review.code_box_key)
    files = if pull.head_sha == review.head_sha && pull.base_sha == base_sha
      Integrations::ReviewHost.changed_files(@row, pull)
    else
      Integrations::ReviewHost.sandbox_files(@row, @checkout, base_sha: base_sha, key: review.code_box_key)
    end
    @files = files
    @diffs = Integrations::ReviewHost.diffs(@row, files, checkout: @checkout, base_sha: base_sha, key: review.code_box_key)
    @patches = files.each_with_object({}) { |file, patches| patches[file.path] = file.patch.to_s }
    @diffs.select(&:read?).each { |diff| @patches[diff.path] = diff.text }
    left = @diffs.reject(&:read?).map { |diff| { "path" => diff.path, "reason" => diff.left_out } }
    review.update!(left_out: (review.left_out.reject { |item| left.any? { |each| each["path"] == item["path"] } } + left))
  end

  def review_parts!
    parts = FirefightAi::PullRequestReviewer.parts(ordered.map { |diff| [ diff.path, diff.text ] })
    chat = review.chat || Chat.open!(owner: review, workspace: review.workspace, model_choice: choice)
    agent = PullRequestReview::Agent.new(review, chat: chat)
    tools, deferred = agent.tools(choice)
    finish = PullRequestReview::FinishPart.new
    reviewer.open(chat, tools: tools + [ PullRequestReview::ReportFinding.new(self), finish ], deferred_tools: deferred, overview: overview(parts))

    # A file split across parts is reviewed once its last piece is.
    last_part = parts.each_with_index.with_object({}) { |(part, index), last| part.paths.each { |path| last[path] = index } }
    parts.each_with_index do |part, index|
      next if (part.paths - review.reviewed_paths).empty?

      finish.reset!
      outcome = reviewer.review_part(
        chat: chat, part: part, number: index + 1, total: parts.size, budget: budget, purse: purse, answered: -> { finish.finished? }, canceled: canceled
      ) { |turn| review.spent!(turns_used: turn.turns_used, spent_micros: turn.spent_micros) }
      review.spent!(turns_used: outcome.turns_used, spent_micros: outcome.spent_micros)
      raise LeaseLost if outcome.status == FirefightAi::AgentLoop::STATUS_CANCELED

      if outcome.status == FirefightAi::AgentLoop::STATUS_ANSWERED
        review.update!(reviewed_paths: (review.reviewed_paths + part.paths.select { |path| last_part[path] == index }).uniq)
      else
        stopped!(parts.drop(index), outcome.status)
        break
      end
    end
  end

  # The parts the review did not finish, left out with why, so its summary says what it did not read.
  def stopped!(parts, status)
    reason = status == FirefightAi::AgentLoop::STATUS_OUT_OF_BUDGET ? BUDGET_SPENT : OUT_OF_STEPS
    paths = parts.flat_map(&:paths).uniq - review.reviewed_paths
    review.update!(left_out: review.left_out + paths.map { |path| { "path" => path, "reason" => reason } })
  end

  def conclude!
    standing = review.findings.reload.standing.to_a
    summary = FirefightAi::ReviewSummarizer.new(review.workspace, inferable: review, choice: choice).summarize(
      pull_request: "#{@pull.title}\n\n#{@pull.body}", files: files_text, reach: context.reach,
      findings: standing.map { |finding| "- #{finding.header}#{' | serious' if finding.serious}: #{finding.claim} (#{finding.path})" }.join("\n")
    )
    review.concluded!(summary: summary.summary, risk: summary.risk, risk_reason: summary.risk_reason)
  end

  def reviewer = @reviewer ||= FirefightAi::PullRequestReviewer.new(review.workspace, inferable: review, choice: choice)

  # The turns allowed are counted per part, from what the review used before it.
  def budget
    FirefightAi::AgentLoop::Budget.new(max_spend_cents: review.max_spend_cents, max_turns: review.turns_used + FirefightAi::PullRequestReviewer::TURNS_PER_PART,
                                       turns_used: review.turns_used, spent_micros: purse.spent)
  end

  def ordered
    @diffs.select(&:read?).each_with_index.sort_by { |diff, index| [ KIND_ORDER.index(CodeChange.kind_for(diff.path)) || KIND_ORDER.size, index ] }.map(&:first)
  end

  def overview(parts)
    in_part = parts.each_with_index.with_object({}) { |(part, index), found| part.paths.each { |path| found[path] ||= index + 1 } }
    {
      "The pull request" => pull_request_text,
      "Its files" => files_text(in_part),
      "Reading its code" => "The head is #{@checkout.ref} in #{@checkout.repository}, and the base is #{review.base_sha}. " \
                            "Read the code with those as the ref.",
      **context.sections
    }
  end

  def pull_request_text
    described = FirefightAi::Evidence.frame("pull_request_description", @pull.body.presence || "(no description)")
    "#{review.repository} PR ##{review.number}: #{@pull.title}\nBy #{@pull.author || 'someone unknown'}, from #{@pull.head_ref} into #{@pull.base_ref}." \
      "#{' It is a draft.' if @pull.draft}#{" It comes from the fork #{@pull.head_repository}." if @pull.fork?}\n#{described}"
  end

  def files_text(in_part = {})
    @files.map do |file|
      left = @diffs.find { |diff| diff.path == file.path }&.left_out
      where = left ? "left out, #{left}" : (in_part[file.path] && "part #{in_part[file.path]}")
      "- #{file.path} (#{file.status}#{", was #{file.previous_path}" if file.previous_path}, +#{file.additions} -#{file.deletions})#{" #{where}" if where}"
    end.join("\n")
  end

  def context = @context ||= PullRequestReview::Context.new(review, agent_principal)

  def agent_principal = SystemAgent.investigator

  def incident_named(identifier)
    return if identifier.blank?

    review.workspace.incidents.where(deleted_at: nil).find_by("lower(identifier) = ?", identifier.to_s.strip.downcase)
  end

  def url_helpers = Rails.application.routes.url_helpers
end

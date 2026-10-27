# A pull request review with its code host and model stubbed: a GitHub connection whose pull request, files and
# checkout are what the test says, a reviewer that reports what the test scripts and a verifier that settles as it says.
module PullRequestReviewTestHelper
  REVIEW_HEAD = "c4e4267d46e638ac6f257d117ab448c280d01c0b".freeze
  REVIEW_BASE = "b586e23aa0e1f6c7c2f2b0c3d4e5f60718293a4b".freeze

  # Plays the reviewer: each part runs the block given for it with the tools the review handed over, then finishes it.
  class ScriptedReviewer
    attr_reader :opened, :parts_seen

    def initialize(script, outcomes)
      @script = script
      @outcomes = outcomes
      @parts_seen = []
    end

    def open(_chat, tools:, overview:, deferred_tools: [])
      @tools = tools.index_by(&:name)
      @opened = overview
    end

    def review_part(part:, number:, budget:, purse:, answered:, **)
      @parts_seen << [ number, part.paths, budget.max_turns ]
      status = @outcomes.fetch(number - 1, FirefightAi::AgentLoop::STATUS_ANSWERED)
      @script.call(number, @tools, part)
      @tools.fetch(PullRequestReview::FinishPart::NAME).execute(reviewed: "Read it.") if status == FirefightAi::AgentLoop::STATUS_ANSWERED
      purse.add(10_000)
      FirefightAi::AgentLoop::Outcome.new(status: answered.call ? FirefightAi::AgentLoop::STATUS_ANSWERED : status, turns_used: budget.turns_used + 3, spent_micros: purse.spent)
    end
  end

  # Plays the check: settles each finding with the next settlement the test lists.
  class ScriptedVerifier
    attr_reader :asked

    def initialize(settlements)
      @settlements = settlements
      @asked = []
    end

    def run(tools:, finding:, earlier:, context:, settled:, **)
      @asked << { finding: finding, earlier: earlier, context: context }
      settlement = @settlements.shift
      tools.find { |tool| tool.name == PullRequestReview::SettleFinding::NAME }.call(**settlement) if settlement
      yield FirefightAi::AgentLoop::Turn.new(turns_used: 2, spent_micros: 5_000) if block_given?
      FirefightAi::AgentLoop::Outcome.new(status: settled.call ? FirefightAi::AgentLoop::STATUS_ANSWERED : FirefightAi::AgentLoop::STATUS_OUT_OF_TURNS,
                                          turns_used: 2, spent_micros: 5_000)
    end
  end

  def review_connection(workspace)
    integration = Integration.create!(workspace: workspace, kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
  end

  def review_pull(head_sha: REVIEW_HEAD, base_sha: REVIEW_BASE)
    Integrations::ReviewHost::PullRequest.new(
      repository: "acme/api", number: 7, title: "Retry checkout", body: "Retries a failed charge.", author: "ada", url: "https://github.com/acme/api/pull/7",
      state: Integrations::ReviewHost::STATE_OPEN, base_ref: "main", base_sha: base_sha, head_ref: "retry", head_sha: head_sha
    )
  end

  def review_file(path, patch)
    Integrations::ReviewHost::ChangedFile.new(path: path, status: Integrations::ReviewHost::STATUS_MODIFIED, additions: patch.lines.count { |line| line.start_with?("+") },
                                              patch: patch)
  end

  def stub_review_host(row, files, paths: nil)
    Integrations::ReviewHost.stubs(:pull_request).returns(review_pull)
    Integrations::ReviewHost.stubs(:checkout!).returns(Integrations::ReviewHost::Checkout.new(repository: "acme/api", ref: REVIEW_HEAD, paths: paths || files.map(&:path)))
    Integrations::ReviewHost.stubs(:changed_files).with(row, anything).returns(files)
  end

  def stub_review_model(reviewer, verifier, summary: review_summary)
    FirefightAi.stubs(:model_for).returns(FirefightAi::ModelChoice.new(model: "claude-sonnet-4-5", provider: "anthropic"))
    FirefightAi::PullRequestReviewer.stubs(:new).returns(reviewer)
    FirefightAi::FindingVerifier.stubs(:new).returns(verifier)
    FirefightAi::ReviewSummarizer.any_instance.stubs(:summarize).returns(summary)
    PullRequestReview::Agent.any_instance.stubs(:tools).returns([ [], [] ])
  end

  def review_summary(risk: "high", spent_micros: 0)
    FirefightAi::ReviewSummarizer::Summary.new(summary: "Retries a failed charge.", risk: risk, risk_reason: "It can charge twice.", spent_micros: spent_micros)
  end

  def reported(path: "app/jobs/charge_job.rb", line: 3, claim: "Queue the retry for its backoff delay", evidence: nil, **overrides)
    {
      "path" => path, "line" => line, "category" => PullRequestReview::Finding::CATEGORY_STABILITY, "severity" => PullRequestReview::Finding::SEVERITY_MAJOR,
      "effort" => PullRequestReview::Finding::EFFORT_QUICK_WIN, "serious" => false, "claim" => claim, "why" => "It retries at once.",
      "failure_chain" => [ "A charge fails", "The retry runs at once and fails again" ],
      "evidence" => evidence || [ { "kind" => PullRequestReview::Finding::EVIDENCE_CODE, "reference" => "#{path}:#{line}", "title" => "The retry" } ],
      "agent_instructions" => "In #{path}, wait before retrying."
    }.merge(overrides)
  end
end

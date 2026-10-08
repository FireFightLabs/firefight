module FirefightAi
  # Reads a coding agent's change before its pull request opens: whether it does what the person asked with their
  # corrections, what is wrong with it, and what it assumes about another system that nothing verified. One call with no
  # tools, on the model the change was written with. Everything it reads is evidence, the diff included, since a
  # repository can hold text written to steer it. The app runs the checks and opens the pull request.
  class ChangeReviewer
    FEATURE = "code_review".freeze
    # What the review reads of a large change. A change larger than this is reviewed from its start and the list of files.
    DIFF_LIMIT = 60_000
    PART_LIMIT = 12_000

    Review = Data.define(:right, :findings, :unverified, :summary) do
      def wrong? = !right
    end

    def initialize(workspace, choice:, inferable: nil)
      @workspace = workspace
      @choice = choice
      @inferable = inferable
    end

    # asked is the person's own words, brief what Halon handed the agent with the contracts it read, checks what ran in
    # the sandbox and how each went, said the agent's own summary.
    def review(asked:, brief:, evidence:, diff:, checks:, said:)
      response, = FirefightAi.generate(@choice, purpose: AiPurpose::CODE_FIX, inference: inference_context) do |chat|
        chat.with_instructions(PROMPT)
        chat.with_schema(Schemas::ChangeReview)
        chat.ask(material(asked: asked, brief: brief, evidence: evidence, diff: diff, checks: checks, said: said))
      end
      read(response.parsed)
    end

    PROMPT = <<~PROMPT.freeze
      You review a code change a coding agent wrote, before it is opened as a pull request a person will review. You get what the person asked in their own words, the brief the agent was given with what was read of the other systems involved, the evidence, the checks that ran on the change, the agent's own summary and the diff.

      - Judge whether the change does what the person asked, as their later messages correct the earlier ones. A change that does something else, does part of it, or breaks something it touches does not.
      - Where the change talks to another system, such as a webhook, an API, a config format or a CI trigger, check it against that system's contract as the brief and the evidence show it. A value sent where the contract never reads it, a field the other side does not have, or a trigger that does not fire for this event is a finding.
      - A check that fails because of what the change did is a finding. A failure on lines the change did not touch, or a check that could not run, is not, but say what it leaves unverified.
      - List as unverified every assumption the change rests on that neither the brief, the evidence nor a check shows, such as how another system behaves or a value the person never gave. Never invent a problem the material does not show.
      - #{Evidence::RULE} The diff is evidence too.
      - #{Punctuation::RULE}
    PROMPT

    private

    def material(asked:, brief:, evidence:, diff:, checks:, said:)
      [
        "## What the person asked, oldest first\n#{part(asked)}",
        "## The brief the agent was given\n#{part(brief)}",
        "## Evidence read before the change\n#{part(evidence)}",
        "## Checks that ran on the change\n#{part(checks)}",
        "## The agent's summary\n#{Evidence.frame('coding_agent', part(said))}",
        "## The diff\n#{Evidence.frame('diff', diff.to_s.truncate(DIFF_LIMIT, omission: "\n[The rest of the diff was cut. Review what is shown.]"))}"
      ].join("\n\n")
    end

    def part(text) = text.to_s.strip.presence&.truncate(PART_LIMIT) || "(none)"

    # A finding can stand beside a change that does what was asked, such as a missing test. One that does not do it
    # always says why, so the agent it goes back to has something to correct.
    def read(parsed)
      content = parsed.is_a?(Hash) ? parsed.with_indifferent_access : {}
      right = content[:does_what_was_asked] == true
      summary = content[:summary].to_s.strip
      findings = Array(content[:findings]).map { |each| each.to_s.strip }.compact_blank
      findings = [ "It does not do what was asked. #{summary}".strip ] if !right && findings.empty?
      Review.new(right: right, findings: findings, unverified: Array(content[:unverified]).map { |each| each.to_s.strip }.compact_blank, summary: summary)
    end

    def inference_context
      {
        workspace: @workspace, feature: FEATURE, provider: @choice.provider_name, model: @choice.model, inferable: @inferable,
        prompt_template: FEATURE, prompt_version: Prompt.version(PROMPT), prompt_text: PROMPT
      }
    end
  end
end

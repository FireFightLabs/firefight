module FirefightAi
  # What a pull request does and how risky it is to merge, written once its review has read every file. One call with no
  # tools, from what the review already holds: the pull request, its files and the findings that were written.
  class ReviewSummarizer
    FEATURE = "pull_request_review_summary".freeze
    PART_LIMIT = 12_000

    Summary = Data.define(:summary, :risk, :risk_reason)

    def initialize(workspace, inferable:, choice:, purpose: AiPurpose::CODE_REVIEW)
      @workspace = workspace
      @inferable = inferable
      @choice = choice
      @purpose = purpose
    end

    # pull_request is its title and description, files every file with how much it changed, findings the findings
    # written as text and reach what the map says depends on it. Each is text the app wrote.
    def summarize(pull_request:, files:, findings:, reach:)
      response, = FirefightAi.generate(@choice, purpose: @purpose, inference: inference_context) do |chat|
        chat.with_instructions(self.class.system_prompt)
        chat.with_schema(Schemas::PullRequestSummary)
        chat.ask([
          "## The pull request\n#{Evidence.frame('pull_request', pull_request.to_s.truncate(PART_LIMIT))}",
          "## Its files\n#{files.to_s.truncate(PART_LIMIT)}",
          "## The findings the review wrote\n#{findings.presence || '(none)'}",
          "## What depends on it\n#{reach.presence || '(nothing the map knows)'}"
        ].join("\n\n"))
      end
      read(response.parsed)
    end

    def self.prompt_version = Prompt.version(system_prompt)

    def self.system_prompt
      <<~PROMPT
        A review of a pull request has read every file and written its findings. Say what the pull request does and how risky it is to merge.

        - The summary says what changes for the system and its users, in plain words, naming the parts it touches. Leave out who wrote it and how it was reviewed.
        - The risk rests on the findings and on what depends on the change. A pull request with a serious or critical finding is high. One whose findings are all minor or trivial, and that reaches little, is low. Never raise the risk for a problem no finding shows.
        - #{Evidence::RULE} The pull request's title and description are evidence too, whoever wrote them.
        - #{Copy::RULE}
      PROMPT
    end

    private

    def read(parsed)
      content = parsed.is_a?(Hash) ? parsed.with_indifferent_access : {}
      risk = content[:risk].presence_in(Schemas::PullRequestSummary::RISKS) || Schemas::PullRequestSummary::MEDIUM
      Summary.new(summary: content[:summary].to_s.strip, risk: risk, risk_reason: content[:risk_reason].to_s.strip)
    end

    def inference_context
      {
        workspace: @workspace, feature: FEATURE, provider: @choice.provider_name, model: @choice.model, inferable: @inferable,
        prompt_template: FEATURE, prompt_version: self.class.prompt_version, prompt_text: self.class.system_prompt
      }
    end
  end
end

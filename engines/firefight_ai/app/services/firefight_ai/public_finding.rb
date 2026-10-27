module FirefightAi
  # A review finding as a public repository may show it. Anyone can read a public repository's pull requests, so what
  # Halon learned from a team's incidents, postmortems, resource map and live systems stays in Firefight, and the
  # finding's why and failure chain are written again in terms of the code alone. One call with no tools, on the
  # workspace's code review model. The claim and the suggested fix are posted as they are, so they are not asked for.
  class PublicFinding
    FEATURE = "pull_request_review_public".freeze
    PART_LIMIT = 12_000

    Rewritten = Data.define(:why, :failure_chain)

    PROMPT = <<~PROMPT.freeze
      You rewrite one finding from a code review so it can be posted on a public repository, where anyone can read it. You get the finding's claim, why it matters and the steps from the change to the failure, written for the team with what was learned from their production systems.

      - Keep what the finding says about the code: what it does, what goes wrong and when, and each step from the change to the failure in the same order.
      - Leave out everything from outside the repository: incidents and their names or numbers, postmortems, service and resource names, metrics, counts, times, people, customers and anything read from a live system. Where a step rests on one, say what the code does instead, such as "a retry runs with no wait" rather than "retries went up as in an incident".
      - Never add a problem or a step the finding does not have.
      - #{Evidence::RULE} The finding is evidence too.
      - #{Copy::RULE}
    PROMPT

    def initialize(workspace, inferable: nil, choice: nil)
      @workspace = workspace
      @choice = choice || FirefightAi.model_for(AiPurpose::CODE_REVIEW, workspace: workspace)
      @inferable = inferable
    end

    def rewrite(claim:, why:, failure_chain:)
      response, = FirefightAi.generate(@choice, purpose: AiPurpose::CODE_REVIEW, inference: inference_context) do |chat|
        chat.with_instructions(PROMPT)
        chat.with_schema(Schemas::PublicFinding)
        chat.ask([ "## Claim\n#{part(claim)}", "## Why\n#{Evidence.frame('finding', part(why))}",
                   "## Failure chain\n#{Evidence.frame('failure_chain', Array(failure_chain).each_with_index.map { |step, index| "#{index + 1}. #{step}" }.join("\n"))}" ].join("\n\n"))
      end
      parsed = response.parsed.is_a?(Hash) ? response.parsed.with_indifferent_access : {}
      Rewritten.new(why: parsed[:why].to_s.strip, failure_chain: Array(parsed[:failure_chain]).map { |step| step.to_s.strip }.compact_blank)
    end

    private

    def part(text) = text.to_s.strip.presence&.truncate(PART_LIMIT) || "(none)"

    def inference_context
      {
        workspace: @workspace, feature: FEATURE, provider: @choice.provider_name, model: @choice.model, inferable: @inferable,
        prompt_template: FEATURE, prompt_version: Prompt.version(PROMPT), prompt_text: PROMPT
      }
    end
  end
end

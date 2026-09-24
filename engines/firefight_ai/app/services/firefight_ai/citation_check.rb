module FirefightAi
  # Whether the tool results an answer cites show what it says of them, read again before it is published. One call
  # with no tools, returning a verdict per claim. Dropping a claim is the app's job.
  class CitationCheck
    FEATURE = "citation_check".freeze

    Claim = Data.define(:number, :text, :steps)
    # What one step returned, as the run recorded it.
    Source = Data.define(:step, :tool, :text)
    Verdict = Data.define(:number, :shown, :reason)

    def initialize(workspace, inferable:, member: nil)
      @workspace = workspace
      @inferable = inferable
      @member = member
    end

    # A claim the model leaves out is not judged, so it is kept rather than dropped on our failure.
    def check(claims:, sources:)
      return [] if claims.empty?

      response, = FirefightAi.translating_errors do
        Inference.track(inference_context) do
          chat = FirefightAi.chat(model_choice)
          chat.with_instructions(system_prompt)
          chat.with_schema(Schemas::CitationCheck)
          chat.ask(prompt(claims, sources))
        end
      end
      verdicts(response, claims.map(&:number))
    end

    private

    def verdicts(response, numbers)
      content = response.parsed
      rows = content.is_a?(Hash) ? content.with_indifferent_access[Schemas::CitationCheck::ROOT_KEY] : nil

      Array(rows).filter_map do |row|
        row = row.with_indifferent_access
        number = row[:number].to_i
        next unless numbers.include?(number) && [ true, false ].include?(row[:shown])

        Verdict.new(number: number, shown: row[:shown], reason: row[:reason].to_s.strip)
      end.uniq(&:number)
    end

    def prompt(claims, sources)
      listed = claims.map { |claim| "#{claim.number}. #{claim.text} (cites step #{claim.steps.join(', step ')})" }
      read = sources.map { |source| Evidence.frame(source.tool, source.text, step: source.step) }

      <<~PROMPT
        The claims:
        #{listed.join("\n")}

        The results they cite:
        #{read.join("\n\n")}
      PROMPT
    end

    def inference_context
      {
        workspace: @workspace, feature: FEATURE, provider: model_choice.provider_name, model: model_choice.model,
        inferable: @inferable, member: @member,
        prompt_template: FEATURE, prompt_version: Prompt.version(system_prompt), prompt_text: system_prompt
      }
    end

    def model_choice
      @model_choice ||= FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace)
    end

    def system_prompt
      <<~PROMPT
        You check an incident finding against the tool results it cites, before it is published. For each numbered claim, say whether the results it cites show it.

        - Shown means the cited results state the claim, or it follows directly from what they state. Plain rewording is fine.
        - Not shown means the claim goes further than the cited results, names something they do not contain, or rests on a result that says something else.
        - Judge each claim only against the results it cites, never against what you know or what another claim cites.
        - #{Evidence::RULE}
      PROMPT
    end
  end
end

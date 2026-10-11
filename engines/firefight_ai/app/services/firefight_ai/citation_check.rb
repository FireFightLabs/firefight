module FirefightAi
  # Whether the tool results an answer cites show what it says of them, read again before it is published. One call
  # with no tools, returning a verdict per claim. Dropping a claim is the app's job.
  class CitationCheck
    FEATURE = "citation_check".freeze

    Claim = Data.define(:number, :text, :steps)
    # What one step returned, as the run recorded it.
    Source = Data.define(:step, :tool, :text)
    Verdict = Data.define(:number, :shown, :reason)

    # model is a ModelChoice for a check told what to run on, such as a rehearsal's. nil means the workspace's.
    # judgments names how each claim is judged, Configuration#judgments when nil (Judging).
    def initialize(workspace, inferable:, member: nil, model: nil, judgments: nil)
      @workspace = workspace
      @inferable = inferable
      @member = member
      @model_choice = model
      @judgments = judgments
    end

    # A claim the model leaves out is not judged, so it is kept rather than dropped on our failure.
    def check(claims:, sources:)
      return [] if claims.empty?

      judge = Judging.choice_for(@workspace, mode: @judgments)
      return judged(judge, claims, sources) if judge

      response, = FirefightAi.generate(model_choice, purpose: AiPurpose::CITATION_CHECK, inference: inference_context) do |chat|
        chat.with_instructions(system_prompt)
        chat.with_schema(Schemas::CitationCheck)
        chat.ask(prompt(claims, sources))
      end
      verdicts(response, claims.map(&:number))
    end

    # Asked of RubyLLM::Judge for each claim, as how likely the results it cites show it.
    SHOWN_QUESTION = "Do the results this claim cites show it? Judge it only against those results, never against what you " \
                     "know or what another claim cites. Claim %<number>d: %<text>s (cites step %<steps>s)".freeze
    SHOWN_CRITERIA = {
      yes: "The cited results state the claim, or it follows directly from what they state. Plain rewording is fine",
      no: "The claim goes further than the cited results, names something they do not contain, or rests on a result that says something else"
    }.freeze
    JUDGED_REASON = "Judged %<percent>d%% likely that the cited results show it.".freeze
    JUDGMENT_TEMPLATE = "citation_check_judgment".freeze

    private

    def judged(choice, claims, sources)
      questions = claims.to_h do |claim|
        [ "claim_#{claim.number}", { type: :probability, criteria: SHOWN_CRITERIA,
                                     instructions: format(SHOWN_QUESTION, number: claim.number, text: claim.text, steps: claim.steps.join(", step ")) } ]
      end
      judgment = Judging.judge(choice, inference: judgment_context(choice), input: results(sources),
                                       questions: questions)
      claims.filter_map do |claim|
        answer = judgment["claim_#{claim.number}"] or next
        likely = answer.probability.to_f
        Verdict.new(number: claim.number, shown: likely >= Judging::SURE, reason: format(JUDGED_REASON, percent: (likely * 100).round))
      end
    end

    def results(sources) = sources.map { |source| Evidence.frame(source.tool, source.text, step: source.step) }.join("\n\n")

    def judgment_context(choice)
      wording = { question: SHOWN_QUESTION, criteria: SHOWN_CRITERIA }.to_json
      {
        workspace: @workspace, feature: FEATURE, provider: choice.provider_name, model: choice.model, inferable: @inferable, member: @member,
        prompt_template: JUDGMENT_TEMPLATE, prompt_version: Prompt.version(wording), prompt_text: wording
      }
    end

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
      @model_choice ||= FirefightAi.model_for(AiPurpose::CITATION_CHECK, workspace: @workspace)
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

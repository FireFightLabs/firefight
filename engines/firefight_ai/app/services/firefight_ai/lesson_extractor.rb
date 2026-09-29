module FirefightAi
  # Reads what an ended incident taught about the setup, for the next incident to start from. Returns plain lessons
  # and verdicts, and the app decides what to remember.
  class LessonExtractor
    FEATURE = "lessons".freeze
    # Below this the model is guessing, and a wrong lesson costs more than a missing one.
    MIN_CONFIDENCE = 0.7
    MOST = 3
    # Per source, keeping its end, since a transcript's decisive part comes last.
    MAX_SOURCE_CHARS = 40_000

    Lesson = Data.define(:fact, :about, :confidence)
    Verdict = Data.define(:memory_id, :verdict, :correction)
    Result = Data.define(:lessons, :verdicts)
    # What the app hands over: a titled block of text such as the finding, the summary or the postmortem.
    Source = Data.define(:title, :text)
    Known = Data.define(:id, :text)

    def initialize(workspace)
      @workspace = workspace
    end

    # subjects are the names a lesson may be about. known are lessons learned before, for the sources to agree with or
    # contradict.
    def extract(incident, sources:, subjects: [], known: [])
      sources = sources.select { |source| source.text.present? }
      return Result.new(lessons: [], verdicts: []) if sources.empty?

      content = call_ai(incident, prompt(incident, sources, subjects, known)).parsed
      content = content.is_a?(Hash) ? content.with_indifferent_access : {}
      Result.new(lessons: lessons(content, subjects), verdicts: verdicts(content, known))
    end

    private

    def lessons(content, subjects)
      names = subjects.index_by(&:downcase)
      Array(content[Schemas::Lessons::LESSONS_KEY]).filter_map do |row|
        row = row.to_h.with_indifferent_access
        next if row[:confidence].to_f < MIN_CONFIDENCE || row[:fact].blank?

        Lesson.new(fact: row[:fact].to_s.strip, about: names[row[:about].to_s.strip.downcase], confidence: row[:confidence].to_f)
      end.first(MOST)
    end

    def verdicts(content, known)
      ids = known.map(&:id).to_set
      Array(content[Schemas::Lessons::VERDICTS_KEY]).filter_map do |row|
        row = row.to_h.with_indifferent_access
        next unless ids.include?(row[:memory_id].to_s)
        next unless [ Schemas::Lessons::AGREES, Schemas::Lessons::CONTRADICTS ].include?(row[:verdict])

        Verdict.new(memory_id: row[:memory_id].to_s, verdict: row[:verdict], correction: row[:correction].to_s.strip.presence)
      end
    end

    def call_ai(incident, prompt_text)
      response, = FirefightAi.translating_errors do
        Inference.track(
          workspace: @workspace, feature: FEATURE, provider: model_choice.provider_name, model: model_choice.model,
          inferable: incident, prompt_template: FEATURE, prompt_version: Prompt.version(system_prompt), prompt_text: system_prompt
        ) do
          chat = FirefightAi.chat(model_choice)
          chat.with_instructions(system_prompt)
          chat.with_schema(Schemas::Lessons)
          chat.ask(prompt_text)
        end
      end
      response
    end

    def model_choice = @model_choice ||= FirefightAi.model_for(AiPurpose::LESSONS, workspace: @workspace)

    def system_prompt
      <<~PROMPT
        An incident is over. Write down what it taught about this team's setup, so the next incident starts from it.

        A lesson is a lasting fact that would help next time: which service depends on which, what a symptom turned out to
        mean, what the cause was and what fixed it, framed as a fact about the setup rather than a story of the day. For
        example "Checkout keeps sessions in the firefight-prod database" or "A 5xx spike on web after a deploy has meant
        the migration job failed".

        Rules:
        - Only what the sources show. Never guess.
        - At most #{MOST} lessons. An incident that taught nothing lasting should return an empty list, and that is a good answer.
        - Never a live value (a count, a rate, what is failing now), a secret, or anything about a person.
        - Pick about from the names given, copied exactly, or leave it empty.
        - For each lesson learned before, say whether the sources agree with it, contradict it, or say nothing about it. When they contradict it, give what is right instead.
        - Plain sentences, no markdown, no em dashes, no semicolons.
      PROMPT
    end

    def prompt(incident, sources, subjects, known)
      parts = [ "Incident: #{incident.identifier} #{incident.name}" ]
      parts << "Names a lesson may be about:\n#{subjects.map { |name| "- #{name}" }.join("\n")}" if subjects.any?
      parts << "Lessons learned before:\n#{known.map { |each| "- #{each.id}: #{each.text}" }.join("\n")}" if known.any?
      sources.each { |source| parts << "## #{source.title}\n#{source.text.last(MAX_SOURCE_CHARS)}" }
      parts.join("\n\n")
    end
  end
end

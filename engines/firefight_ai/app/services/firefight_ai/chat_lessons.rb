module FirefightAi
  # Reads a chat with Halon once it has gone quiet or ended, for lasting facts about the team's setup worth remembering.
  # One call with no tools, on the workspace's quick model. Returns plain lessons, and the app decides what to remember.
  class ChatLessons
    FEATURE = "chat_lessons".freeze
    # Below this the model is guessing, and a wrong lesson costs more than a missing one.
    MIN_CONFIDENCE = 0.7
    MOST = 3
    # The chat is read from its end, since what was settled comes last.
    MAX_CHARS = 40_000

    Lesson = Data.define(:fact, :about, :confidence)
    # Something the workspace already holds, never to be learned again.
    Remembered = Data.define(:text, :rejected)

    def initialize(workspace, inferable: nil, member: nil)
      @workspace = workspace
      @inferable = inferable
      @member = member
    end

    # transcript is the chat as plain lines. remembered is what the workspace already holds, as plain sentences, rejected
    # ones marked, never to be learned again. Any failure, choosing the model included, is raised as a FirefightAi::Error.
    def extract(transcript:, remembered: [])
      return [] if transcript.blank?

      response, = FirefightAi.translating_errors do
        FirefightAi.generate(model_choice, purpose: AiPurpose::SUMMARY, inference: inference_context) do |chat|
          chat.with_instructions(PROMPT)
          chat.with_schema(Schemas::ChatLessons)
          chat.ask(prompt(transcript, remembered))
        end
      end
      content = response.parsed.is_a?(Hash) ? response.parsed.with_indifferent_access : {}
      Array(content[Schemas::ChatLessons::LESSONS_KEY]).filter_map do |row|
        row = row.to_h.with_indifferent_access
        next if row[:confidence].to_f < MIN_CONFIDENCE || row[:fact].blank?

        Lesson.new(fact: row[:fact].to_s.strip, about: row[:about].to_s.strip.presence, confidence: row[:confidence].to_f)
      end.first(MOST)
    rescue RubyLLM::Error, RubyLLM::ConfigurationError => error
      raise TerminalError.new(error.message, reason: error.class.name.demodulize)
    end

    PROMPT = <<~PROMPT.freeze
      A chat between a team and Halon, their SRE, has finished for now. Write down what it showed about the team's production setup that would still hold next week, so the next chat or investigation starts from it.

      A lesson is a lasting fact about the setup: which service depends on which, where something runs, which branch a service ships from, what a symptom has meant, how the team runs things. For example "Checkout keeps sessions in the firefight-prod database" or "web deploys from the release branch".

      Rules:
      - Only what the chat shows, from what a person said or what a result Halon read showed. Never a guess, and never Halon's own unchecked theory.
      - At most #{MOST} lessons. If the chat taught nothing lasting, return an empty list. That is a good answer, and most chats teach nothing.
      - Never a live value (a count, a rate, what is failing now, a time of day), a secret, or anything about a person.
      - Never write anything already remembered, in any words. One marked rejected is known to be wrong, so never write it either.
      - Set about to the name of the service, catalog entry or resource the fact is about, as the chat writes it, or leave it empty when it is about the whole workspace.
      - Plain sentences, no markdown.
      - #{Copy::RULE}
    PROMPT

    private

    def prompt(transcript, remembered)
      parts = []
      parts << "Already remembered in this workspace:\n#{remembered.map { |each| "- #{each.text}#{' (rejected)' if each.rejected}" }.join("\n")}" if remembered.any?
      parts << "## The chat (chronological)\n#{transcript.last(MAX_CHARS)}"
      parts.join("\n\n")
    end

    def model_choice = @model_choice ||= FirefightAi.model_for(AiPurpose::SUMMARY, workspace: @workspace)

    def inference_context
      {
        workspace: @workspace, feature: FEATURE, provider: model_choice.provider_name, model: model_choice.model,
        inferable: @inferable, member: @member, prompt_template: FEATURE, prompt_version: Prompt.version(PROMPT), prompt_text: PROMPT
      }
    end
  end
end

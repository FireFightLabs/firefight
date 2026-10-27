module FirefightAi
  # Reads how a person treated a pull request Halon opened, what they changed before merging it or why they closed it,
  # and writes at most one lesson for later changes to the same repository. A lesson needs a reason the person stated or
  # a cause that repeats in an earlier pull request, so a one off edit with no word of why teaches nothing. Returns a
  # plain result, and the app decides what to remember.
  class PullRequestLessonExtractor
    FEATURE = "pull_request_lessons".freeze
    # Below this the model is guessing, and a wrong lesson costs more than a missing one.
    MIN_CONFIDENCE = 0.7
    MAX_CHARS = 20_000

    EDITED = "edited".freeze
    CLOSED = "closed".freeze

    # What happened: EDITED or CLOSED, the person, what they wrote (commit messages, comments, a reason the host kept)
    # and what they changed, as a diff, for EDITED.
    Handled = Data.define(:kind, :person, :words, :changes) do
      def initialize(words: "", changes: "", **) = super
    end
    # An earlier pull request Halon opened in the same repository that a person edited or closed, as it was recorded.
    Earlier = Data.define(:label, :kind, :summary)
    Result = Data.define(:lesson, :basis)

    def initialize(workspace)
      @workspace = workspace
    end

    # Nil when there is no lesson, the basis is missing, or it rests on a repeat when no earlier pull request was given.
    def extract(inferable:, repository:, label:, title:, handled:, earlier: [])
      content = call_ai(inferable, prompt(repository, label, title, handled, earlier)).parsed
      content = content.is_a?(Hash) ? content.with_indifferent_access : {}
      lesson = content[:lesson].to_s.squish
      basis = content[:basis].to_s
      return nil if lesson.empty? || content[:confidence].to_f < MIN_CONFIDENCE
      return nil unless [ Schemas::PullRequestLesson::STATED, Schemas::PullRequestLesson::REPEATED ].include?(basis)
      return nil if basis == Schemas::PullRequestLesson::REPEATED && earlier.empty?

      Result.new(lesson: lesson, basis: basis)
    end

    def self.system_prompt
      <<~PROMPT
        Halon, the team's SRE, opened a pull request. A person then either changed it before merging it, or closed it without merging. Work out whether that teaches something Halon should do differently in later changes to the same repository.

        Rules:
        - A lesson needs a basis. Either the person stated why, in a commit message, a comment or the reason they gave for closing it, or an earlier pull request listed shows the same cause. A change with no word of why and nothing like it before is a one off, and teaches nothing. Return an empty lesson then. That is a good answer.
        - A lesson is one sentence about this repository that Halon can follow next time, such as "Migrations in this repository add an index concurrently" or "Changes to the billing service need a feature flag".
        - Never a lesson about a person, a live value, or something that only held for this one change.
        - A formatting or wording edit with no stated reason is not a lesson.
        - Plain sentences, no markdown.
        - #{Copy::RULE}
      PROMPT
    end

    private

    def prompt(repository, label, title, handled, earlier)
      parts = [ "Repository: #{repository}", "Pull request: #{label} #{title}" ]
      parts << (handled.kind == EDITED ? "#{handled.person} changed it before merging." : "#{handled.person} closed it without merging.")
      parts << Evidence.frame("what_they_wrote", handled.words.to_s.last(MAX_CHARS)) if handled.words.present?
      parts << Evidence.frame("what_they_changed", handled.changes.to_s.first(MAX_CHARS)) if handled.changes.present?
      if earlier.any?
        listed = earlier.map { |each| "- #{each.label} (#{each.kind}): #{each.summary}" }.join("\n")
        parts << "Earlier pull requests Halon opened in this repository that a person changed or closed:\n#{listed}"
      end
      parts.join("\n\n")
    end

    def call_ai(inferable, prompt_text)
      response, = FirefightAi.generate(model_choice, purpose: AiPurpose::LESSONS, inference: {
        workspace: @workspace, feature: FEATURE, provider: model_choice.provider_name, model: model_choice.model, inferable: inferable,
        prompt_template: FEATURE, prompt_version: Prompt.version(self.class.system_prompt), prompt_text: self.class.system_prompt
      }) do |chat|
        chat.with_instructions(self.class.system_prompt)
        chat.with_schema(Schemas::PullRequestLesson)
        chat.ask(prompt_text)
      end
      response
    end

    def model_choice = @model_choice ||= FirefightAi.model_for(AiPurpose::LESSONS, workspace: @workspace)
  end
end

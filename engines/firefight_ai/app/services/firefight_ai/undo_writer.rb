module FirefightAi
  # Writes the plan that reverses a fix that was applied, from what each step actually did: its kind, what it called with
  # what, what came back and the undo note it was written with. Returns the plan as the fix shape the app checks, so a
  # step naming a tool the workspace cannot run is refused there like any other.
  class UndoWriter
    FEATURE = "undo".freeze
    MAX_RESULT_CHARS = 2_000

    # What one applied step did, as plain data.
    Step = Data.define(:position, :kind, :description, :repository, :tool, :arguments, :result, :undo, :status)

    def initialize(workspace)
      @workspace = workspace
    end

    # tools are the names of the tools that change things the workspace can run, which an action may name.
    def write(steps, summary:, tools:, inferable:)
      content = call_ai(prompt(steps, summary, tools), inferable).parsed
      content = content.is_a?(Hash) ? content.with_indifferent_access : {}
      {
        "summary" => content[:summary].to_s, "verify" => content[:verify].presence,
        "steps" => Array(content[Schemas::UndoPlan::STEPS_KEY]).map { |row| step(row.to_h.with_indifferent_access) }
      }
    end

    private

    def step(row)
      {
        "kind" => row[:kind].to_s, "description" => row[:description].to_s, "repository" => row[:repository].presence,
        "tool" => row[:tool].presence, "arguments" => arguments(row[:arguments]), "missing" => row[:missing].presence,
        "depends_on" => Array(row[:depends_on]).map(&:to_i)
      }.compact
    end

    # Left as written when it is not an object, so the app's check refuses it with why.
    def arguments(text)
      return nil if text.blank?

      JSON.parse(text)
    rescue JSON::ParserError
      text
    end

    def call_ai(prompt_text, inferable)
      choice = FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace)
      response, = FirefightAi.translating_errors do
        Inference.track(
          workspace: @workspace, feature: FEATURE, provider: choice.provider_name, model: choice.model, inferable: inferable,
          prompt_template: FEATURE, prompt_version: Prompt.version(system_prompt), prompt_text: system_prompt
        ) do
          chat = FirefightAi.chat(choice)
          chat.with_instructions(system_prompt)
          chat.with_schema(Schemas::UndoPlan)
          chat.ask(prompt_text)
        end
      end
      response
    end

    def system_prompt
      <<~PROMPT
        A fix was applied to a production system. Write the steps that put back what it changed.

        Rules:
        - Undo only what a step changed. A step that failed, was skipped or was declined changed nothing and needs no undo.
        - Go newest first, so the last change is put back first, and make a step wait for any undo it depends on.
        - Use each step's undo note and what it actually returned, such as an id or a previous value, so the undo names exactly what to put back.
        - A tool step is undone by a tool step, naming one of the tools given, copied exactly, with its arguments as a JSON object.
        - A code change that opened a pull request is undone by closing that pull request when it was never merged, which is a step for a person or a tool that closes it, and by a pull_request in the same repository that reverts it when it was merged. Say which, and name the pull request.
        - A step a person did is undone by a step for a person, saying what they put back.
        - When nothing can be put back from what you are given, make it a step for a person and say what is missing.
        - Never invent a value you were not given. Never put a credential in a step.
        - #{Evidence::RULE}
        - Plain sentences, no markdown, no em dashes, no semicolons.
      PROMPT
    end

    def prompt(steps, summary, tools)
      parts = [ "The fix: #{summary}" ]
      parts << "Tools that change things here:\n#{tools.map { |name| "- #{name}" }.join("\n")}" if tools.any?
      steps.each do |step|
        parts << [
          "## Step #{step.position}, #{step.kind}, #{step.status}",
          step.description,
          ("Repository: #{step.repository}" if step.repository.present?),
          ("Tool: #{step.tool}" if step.tool.present?),
          ("Called with: #{step.arguments.to_json}" if step.arguments.present?),
          ("What came back:\n#{Evidence.frame(step.tool.presence || step.kind, step.result.to_s.last(MAX_RESULT_CHARS))}" if step.result.present?),
          ("Undo note: #{step.undo}" if step.undo.present?)
        ].compact.join("\n")
      end
      parts.join("\n\n")
    end
  end
end

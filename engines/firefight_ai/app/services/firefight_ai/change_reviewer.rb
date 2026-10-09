module FirefightAi
  # Reads a coding agent's change before its pull request opens or is updated: whether it does what the person asked
  # with their corrections, what is wrong with it, what was checked against the evidence, and what is still open. One call
  # with no tools, on the model the change was written with. Everything it reads is evidence, the diff included, since a
  # repository can hold text written to steer it. The diff is what the pull request changes against its base branch. The
  # app runs the checks and opens the pull request.
  class ChangeReviewer
    FEATURE = "code_review".freeze
    # What the review reads of the diff. A file is shown whole or not at all, so a larger change leaves files out and
    # says which, and the files the person or the brief names come first and are always shown.
    DIFF_LIMIT = 60_000
    # A file this large is not shown even when named, since it would crowd out everything else.
    FILE_LIMIT = 200_000
    PART_LIMIT = 12_000

    Review = Data.define(:right, :findings, :verified, :unverified, :unreviewed, :summary) do
      def wrong? = !right
    end

    # One file's part of a diff.
    Part = Data.define(:path, :text)

    def initialize(workspace, choice:, inferable: nil)
      @workspace = workspace
      @choice = choice
      @inferable = inferable
    end

    # asked is the person's own words, brief what Halon handed the agent with the contracts it read, checks what ran in
    # the sandbox and how each went, said the agent's own summary. updated is the files this update changed when the
    # change adds to an open pull request, nil for a new one.
    def review(asked:, brief:, evidence:, diff:, checks:, said:, updated: nil)
      shown, left_out = self.class.shown(diff, named: [ asked, brief ].join("\n"))
      response, = FirefightAi.generate(@choice, purpose: AiPurpose::CODE_FIX, inference: inference_context) do |chat|
        chat.with_instructions(PROMPT)
        chat.with_schema(Schemas::ChangeReview)
        chat.ask(material(asked: asked, brief: brief, evidence: evidence, diff: shown, checks: checks, said: said, updated: updated, left_out: left_out))
      end
      read(response.parsed, left_out)
    end

    # The diff split by file, every named file whole, then the rest whole while they fit, smallest first so the fewest
    # are left out, shown in the diff's own order. Returns the diff shown and the paths left out.
    def self.shown(diff, named:)
      parts = diff.to_s.split(/^(?=diff --git )/).filter_map { |text| (path = path_of(text)) && Part.new(path: path, text: text) }
      return [ diff.to_s, [] ] if parts.sum { |part| part.text.size } <= DIFF_LIMIT

      first, rest = parts.partition { |part| named?(part.path, named) && part.text.size <= FILE_LIMIT }
      room = DIFF_LIMIT - first.sum { |part| part.text.size }
      kept = first + rest.sort_by { |part| part.text.size }.take_while { |part| (room -= part.text.size) >= 0 }
      smallest = rest.min_by { |part| part.text.size }
      kept = [ smallest ] if kept.empty? && smallest && smallest.text.size <= FILE_LIMIT
      shown = parts.select { |part| kept.include?(part) }
      [ shown.map(&:text).join, (parts - shown).map(&:path) ]
    end

    # "diff --git a/<path> b/<path>", the same path twice since renames are not followed.
    def self.path_of(text)
      header = text.lines.first.to_s.chomp.delete_prefix("diff --git ")
      size = (header.size - 5) / 2
      header[2, size] if size.positive?
    end

    def self.named?(path, text) = text.include?(path) || (File.basename(path).size > 3 && text.include?(File.basename(path)))

    private_class_method :path_of, :named?

    PROMPT = <<~PROMPT.freeze
      You review a code change before Firefight opens it as a pull request, or adds it to one, for a person to review. You get what the person asked in their own words, the instructions the coding agent was given with what was read of the other systems involved, the evidence, the checks that ran, the coding agent's own summary and the diff.

      - The diff is what the pull request changes against its base branch. What a merge brought in from the base branch is not in it and is not part of this change. When the change adds to an open pull request, the files this update changed are listed too.
      - Judge whether the change does what the person asked, as their later messages correct the earlier ones. A change that does something else, does part of it, or breaks something it touches does not.
      - Where the change talks to another system, such as a webhook, an API, a config format or a CI trigger, check it against that system's contract as the material shows it. A value sent where the contract never reads it, a field the other side does not have, or a trigger that does not fire for this event is a finding.
      - Before you call anything open, look for the answer in the material: the evidence, documentation it quotes, an error message the other system returned that states a rule (such as which characters a name may hold), the checks and the agent's summary. When the material answers it, check the change against it and put it under verified, saying what you checked it against.
      - A check that fails because of what the change did is a finding. A failure on lines the change did not touch is not. A check that could not run here was missing something the change does not provide, such as a database, and is reported on its own, so it is never a finding or an open question.
      - Firefight commits the change, pushes it and updates the pull request only after this review, so that none of that has happened yet is expected and never a point.
      - Open questions are only what genuinely could not be checked from the material and would matter if it were wrong, such as how another system behaves where nothing shows it. Never list something the material answers, a check that could not run here, a file you were not shown, or a general doubt. Never invent a problem the material does not show.
      - Write for the person who will review the pull request: short plain sentences they understand on first read, each naming the file or the value. No jargon, no metaphors, and no words about how the work was done, such as brief, session, sandbox or agent.
      - #{Evidence::RULE} The diff is evidence too.
      - #{Copy::RULE}
    PROMPT

    private

    def material(asked:, brief:, evidence:, diff:, checks:, said:, updated:, left_out:)
      [
        "## What the person asked, oldest first\n#{part(asked)}",
        "## The instructions the coding agent was given\n#{part(brief)}",
        "## Evidence read before the change\n#{part(evidence)}",
        "## Checks that ran on the change\n#{part(checks)}",
        "## The coding agent's summary\n#{Evidence.frame('coding_agent', part(said))}",
        ("## Files this update changed\n#{updated.any? ? updated.map { |path| "- #{path}" }.join("\n") : '(none of the pull request\'s files, only a merge)'}" unless updated.nil?),
        ("## Files not shown, since the change is too large to review whole\n#{left_out.map { |path| "- #{path}" }.join("\n")}" if left_out.any?),
        "## The diff of the pull request against its base branch\n#{Evidence.frame('diff', diff)}"
      ].compact.join("\n\n")
    end

    def part(text) = text.to_s.strip.presence&.truncate(PART_LIMIT) || "(none)"

    # A finding can stand beside a change that does what was asked, such as a missing test. One that does not do it
    # always says why, so the agent it goes back to has something to correct.
    def read(parsed, left_out)
      content = parsed.is_a?(Hash) ? parsed.with_indifferent_access : {}
      right = content[:does_what_was_asked] == true
      summary = content[:summary].to_s.strip
      findings = lines(content[:findings])
      findings = [ "It does not do what was asked. #{summary}".strip ] if !right && findings.empty?
      Review.new(right: right, findings: findings, verified: lines(content[:verified]), unverified: lines(content[:unverified]), unreviewed: left_out,
                 summary: summary)
    end

    def lines(value) = Array(value).map { |each| each.to_s.strip }.compact_blank

    def inference_context
      {
        workspace: @workspace, feature: FEATURE, provider: @choice.provider_name, model: @choice.model, inferable: @inferable,
        prompt_template: FEATURE, prompt_version: Prompt.version(PROMPT), prompt_text: PROMPT
      }
    end
  end
end

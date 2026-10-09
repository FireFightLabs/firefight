module Integrations
  # What Firefight writes about a code change it opened or added to: the pull request's body, the comment when it adds
  # to an open one, and the answer Halon tells the person from. Each leads with what the change does, then what was
  # verified and how, what could not run here and why, and only the questions still open, in plain words for whoever
  # reads the pull request. Every list is of what the pull request changes against its base, so what a merge brought from
  # the base is never in it.
  module CodeWriteUp
    FILES_LISTED = 30
    FOOTER = "Written by Halon. Review it like any other change before merging.".freeze
    # The section for what could not run here, which the coding agent's summary uses as its heading too.
    NOT_RUN = "Could not run here".freeze
    # Said when the repository has no CI, after the host's own words for where it looked.
    NO_CI = "With no CI, nothing beyond the checks that ran in Firefight's sandbox tested this change, and the owner's review decides whether it is ready.".freeze

    # The description is made from the change, its checks and its review only, never from what Halon told the coding
    # agent, since a repository may be public and the brief holds instructions and what was read of live systems. lead is
    # what the review says the change does, or the title when the review did not run. warning is the CI warning or nil,
    # and no_ci the code host's words that the repository has no CI, or nil when it has.
    def self.body(title:, warning:, reviewed:, change:, no_ci: nil)
      lead = reviewed&.summary.presence || title
      text = [ lead, warning, *sections(reviewed, change, bold: true), without_ci(no_ci, bold: true), files("**Files**", change.counts), FOOTER ]
      Chat::SecretFree.redacted(text.compact.join("\n\n"))
    end

    # Said on an open pull request the change was added to: what this update did, then the same sections.
    def self.comment(lead:, warning:, reviewed:, change:, base:, no_ci: nil)
      text = [ lead, warning, update_words(change, base), *sections(reviewed, change, bold: true), without_ci(no_ci, bold: true),
               "Added by Halon in #{change.commit[0, 12]}. Review it like any other change before merging." ]
      Chat::SecretFree.redacted(text.compact.join("\n\n"))
    end

    # What Halon reads back once the change opened or was added, to tell the person in the same terms.
    def self.answer(done:, warning:, reviewed:, change:, base:, updating:, no_ci: nil)
      changed = updating ? update_words(change, base) : files("Changes:", change.counts)
      [ done, warning, changed, *sections(reviewed, change, bold: false), without_ci(no_ci, bold: false) ].compact.join("\n\n")
    end

    def self.without_ci(said, bold:)
      return if said.blank?

      "#{bold ? '**No CI**' : 'No CI:'}\n#{Sentence.ended(said)} #{NO_CI}"
    end

    # What could not run is the checks that could not, then what the agent's summary said it could not run.
    def self.sections(reviewed, change, bold:)
      checks = Array(change.checks)
      verified = checks.select(&:passed?).map { |check| "`#{check.name}` passed." } + Array(reviewed&.verified)
      not_run = checks.select(&:could_not_run?).map { |check| "`#{check.name}`: #{check.reason}." } + change.not_run.map { |line| Sentence.ended(line) }
      failed = checks.select { |check| !check.passed? && !check.could_not_run? }.map { |check| "`#{check.name}` #{check.status}." }
      [
        section("Verified", verified, bold),
        section(NOT_RUN, not_run, bold),
        section("Checks that did not pass", failed, bold),
        section("Found in review", Array(reviewed&.findings), bold),
        section("Open questions", Array(reviewed&.unverified), bold),
        (section("Not reviewed, since the change is too large to review whole", reviewed.unreviewed.map { |path| "`#{path}`" }, bold) if reviewed&.unreviewed.present?)
      ].compact
    end

    def self.section(title, lines, bold)
      return if lines.empty?

      "#{bold ? "**#{title}**" : "#{title}:"}\n#{lines.map { |line| "- #{line}" }.join("\n")}"
    end

    # Each file the pull request changes with its lines added and removed, the first FILES_LISTED of them.
    def self.files(title, counts)
      return if counts.blank?

      lines = counts.first(FILES_LISTED).map { |path, (added, removed)| "- `#{path}` #{added.nil? ? '(binary)' : "(+#{added} -#{removed})"}" }
      lines << "- and #{counts.size - FILES_LISTED} more" if counts.size > FILES_LISTED
      "#{title}\n#{lines.join("\n")}"
    end

    # The files of the pull request this update changed, and whether it merged the base in. A merge alone changes none.
    def self.update_words(change, base)
      updated = change.updated_paths
      merged = ("It merges #{base} into this branch." if change.merged)
      return [ "This update changes no file this pull request changes.", merged ].compact.join(" ") if updated.empty?

      [ "Changed in this update: #{updated.map { |path| "`#{path}`" }.to_sentence}.", merged ].compact.join(" ")
    end

    private_class_method :sections, :section, :files, :update_words, :without_ci
  end
end

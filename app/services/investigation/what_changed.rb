# Before the agent starts, reads where the clues point and what changed before the trouble began, the first thing an
# engineer asks. The clues come from Firefight's own records. The changes come from the code host through the same
# gateway wrapped tool the agent would call, so the answer is a numbered step a finding can cite. Both are kept with
# the facts, so a resumed run does not ask again.
class Investigation::WhatChanged
  CLUES_KEY = "clues".freeze
  KEY = "what_changed".freeze
  NOT_CONNECTED = "What changed was not read: no code host connection can answer. Connect GitHub and switch on changes_before.".freeze
  # When no alert or report said when it began, the start is a guess, so the detail reaches further back.
  WINDOW_HOURS = 6
  ESTIMATED_WINDOW_HOURS = 24

  def initialize(investigation)
    @investigation = investigation
  end

  def note!
    facts = @investigation.seed_pack
    return facts if facts.key?(KEY)

    clues = Investigation::Clues.new(@investigation).gather
    @investigation.update!(seed_pack: facts.merge(CLUES_KEY => clues, KEY => changes(clues)))
    @investigation.seed_pack
  end

  private

  # Each connection sees only its own repositories, so every one is asked, each answer its own step.
  def changes(clues)
    tools = changes_before_tools
    return NOT_CONNECTED if tools.empty?

    tools.map { |tool| Chat::Tools::Connection.new(@investigation, tool).call(**arguments(clues)) }.join("\n\n")
  end

  def arguments(clues)
    started = clues.fetch("started")
    {
      "at" => started["at"], "started_from" => started["source"],
      "window_hours" => started["estimated"] ? ESTIMATED_WINDOW_HOURS : WINDOW_HOURS,
      "repositories" => values(clues, "repositories"), "names" => values(clues, "names"),
      "paths" => clues["paths"].map { |frame| "#{frame['value']}:#{frame['line']}" },
      "error_texts" => values(clues, "error_texts"), "commits" => values(clues, "commits")
    }.compact_blank
  end

  def values(clues, key) = Array(clues[key]).map { |clue| clue["value"] }

  def changes_before_tools
    Integration::Tool.in_workspace(@investigation.workspace)
      .where(name: Integrations::Packs::Github::CHANGES_BEFORE, integrations: { provider: Integrations::GithubApp::PROVIDER_KEY })
      .order(:created_at).to_a
  end
end

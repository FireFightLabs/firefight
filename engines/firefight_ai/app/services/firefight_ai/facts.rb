module FirefightAi
  # The facts a run starts from, as the first message hands them over. Each part the facts hold is explained beside them,
  # so a run reads what a part means where it meets it, and the prompt carries nothing for a part a run does not have.
  module Facts
    # By the key each part has in the facts, in the order they are explained.
    READING = {
      "handbook" => "handbook is how this workspace works, written by its people. Follow it, and name a page you follow " \
                    "with its link. When a result you read now disagrees with a page, work from the result, say what each " \
                    "shows, and propose the edit with propose_handbook_edit. search_handbook reads a page named but not given whole.",
      "instructions" => "instructions are how people here want you to work, headed by where each applies, the more specific " \
                        "one winning where two differ. They say how to work, and what happened comes from what you read.",
      "memories" => "memories are what this workspace remembers: hunches to check against live results, of which only a " \
                    "confirmed one was vouched for by a person, so say so when you rely on one that is not. When a result " \
                    "contradicts one, dispute it with dispute_memory.",
      "resources" => "resources are where the services involved run on the map, with how many depend on each and what " \
                     "changed on them in the day before. Start from them with the map tools: get_resource for one, " \
                     "get_resource_neighbours and traverse_resource_map for what it depends on and what depends on it, " \
                     "blast_radius for what fails with it, and find_resources for others.",
      "suspects" => "suspects are what changed on the failing resources and their neighbours up to two hops, and the alerts " \
                    "on them, nearest to when the trouble began first. Each is a candidate to check, never a conclusion.",
      "past_incidents" => "past_incidents broke the same way before. A finding_outcome of confirmed makes that answer a worked " \
                          "example, and wrong makes it a mistake to learn from rather than a lead.",
      "directs_halon" => "directs_halon names who directs you in this incident. Notes from responders say who wrote them. When " \
                         "two ask for things that conflict, say so, naming each and what they asked, and follow the one who " \
                         "directs you. When they have not settled it, leave the conflict for them to decide.",
      "on_call" => "on_call means an alert started this run and nobody asked, so nobody may be awake to steer you. Load the " \
                   "on_call_alert skill with use_skill first. It says how to read, who to page and how to write a fix the " \
                   "team let you make on your own."
    }.freeze

    def self.opening(lead, seed_pack)
      held = seed_pack.to_h.transform_keys(&:to_s).reject { |_key, value| value.blank? }
      notes = READING.select { |key, _note| held.key?(key) }.values.map { |note| "- #{note}" }
      "#{[ lead, ("How to read them:\n#{notes.join("\n")}" if notes.any?), JSON.pretty_generate(seed_pack) ].compact.join("\n\n")}\n"
    end
  end
end

module Investigation::Seeding
  extend ActiveSupport::Concern

  # One seeder per subject type. A new kind of subject adds a class and a line here.
  SEEDERS = {
    "Incident" => "Investigation::IncidentSeed",
    # A question asked before anyone declared an incident.
    nil => "Investigation::QuestionSeed"
  }.freeze

  class UnknownSubject < StandardError; end

  # When the facts were read, which every seeder writes.
  KEY_GATHERED_AT = "gathered_at".freeze
  # Where the clues point, for whatever the agent decides to check. Gathering them calls nothing.
  KEY_CLUES = "clues".freeze
  # What the workspace learned about what the incident touches, each a hunch to check.
  KEY_MEMORIES = "memories".freeze
  # How people here want the agent to work on what the incident touches, never evidence.
  KEY_INSTRUCTIONS = "instructions".freeze
  # Which changes to a starting memory the run was already told about, by memory id.
  KEY_TOLD = "told".freeze

  included do
    # Memories and instructions are encrypted where they are kept, so the run's copy of them is too.
    serialize :seed_notes, coder: JSON
    encrypts :seed_notes
  end

  # The notes hold each starting memory's id and the line the run read, and the instructions.
  def self.notes(memories, instructions) = { KEY_MEMORIES => memories, KEY_INSTRUCTIONS => instructions }

  # Gathered once, so every turn and a resumed run read the same facts.
  def build_seed_pack!
    return seed_pack if seed_pack.present?

    subjects = Chat::Memory.subjects_for(incident)
    memories = Chat::Memory.starting_with(workspace, subjects, principal: acting_principal)
    instructions = Chat::Instruction.for_subjects(workspace, subjects).map(&:line)
    update!(seed_pack: seeder.gather.merge(KEY_CLUES => Investigation::Clues.new(self).gather),
            seed_notes: Investigation::Seeding.notes(memories.map { |memory| { "id" => memory.id, "line" => memory.line } }, instructions))
    Chat::Memory.handed_to!(memories, self) if changes_memory?
    seed_pack
  end

  # The facts the run starts from. A starting memory that changed since is marked, so a run that starts again from its
  # record after making room never reads one a person has since set aside as if it still held.
  def starting_facts
    return seed_pack if seed_notes.blank?

    # A rehearsal reads what its original read, never what changed since.
    changes = rehearsal? ? {} : starting_memory_changes
    lines = starting_memories.map { |memory| [ memory["line"], changes[memory["id"]]&.mark ].compact.join(" ") }
    seed_pack.merge(KEY_MEMORIES => lines, KEY_INSTRUCTIONS => Array(seed_notes[KEY_INSTRUCTIONS]))
  end

  # What changed in a starting memory since the run began that it has not been told yet, each as a short note, and
  # remembers they were told. Only the worker holding the run calls it.
  def untold_memory_changes!
    return [] if rehearsal? || seed_notes.blank?

    told = seed_notes[KEY_TOLD] || {}
    fresh = starting_memory_changes.reject { |id, change| told[id] == change.key }
    return [] if fresh.empty?

    update_columns(seed_notes: seed_notes.merge(KEY_TOLD => told.merge(fresh.transform_values(&:key))))
    fresh.values.map(&:note)
  end

  private

  def starting_memories = Array(seed_notes[KEY_MEMORIES]).select { |memory| memory["id"].present? }

  def starting_memory_changes
    ids = starting_memories.map { |memory| memory["id"] }
    found = Chat::Memory.where(workspace: workspace, id: ids).includes(:rejected_by, :replaced_by).index_by(&:id)
    ids.filter_map { |id| (change = Chat::Memory.change_since_start(id, found[id])) && [ id, change ] }.to_h
  end

  def seeder
    class_name = SEEDERS[subject_type]
    raise UnknownSubject, "No seeder for #{subject_type}" unless class_name

    class_name.constantize.new(self)
  end
end

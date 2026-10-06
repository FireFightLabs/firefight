# A run's starting memories and instructions were kept in the plain seed_pack. They move to seed_notes, encrypted like
# the tables they came from, and the pack keeps only facts read from the incident and the map.
class MoveSeedPackMemoriesToEncryptedNotes < ActiveRecord::Migration[8.1]
  MEMORIES = "memories".freeze
  INSTRUCTIONS = "instructions".freeze
  LEADING_ID = /\A(\h{8}-\h{4}-\h{4}-\h{4}-\h{12}) /

  def up
    Investigation.reset_column_information
    packed.find_each do |run|
      pack = run.seed_pack
      memories = Array(pack[MEMORIES]).map { |line| { "id" => line.to_s[LEADING_ID, 1], "line" => line.to_s } }
      run.update_columns(seed_notes: Investigation::Seeding.notes(memories, Array(pack[INSTRUCTIONS])),
                         seed_pack: pack.except(MEMORIES, INSTRUCTIONS))
    end
  end

  def down
    Investigation.reset_column_information
    Investigation.where.not(seed_notes: nil).find_each do |run|
      notes = run.seed_notes || {}
      run.update_columns(seed_pack: run.seed_pack.merge(MEMORIES => Array(notes[MEMORIES]).map { |memory| memory["line"] },
                                                        INSTRUCTIONS => Array(notes[INSTRUCTIONS])), seed_notes: nil)
    end
  end

  private

  def packed = Investigation.where("seed_pack ? :memories OR seed_pack ? :instructions", memories: MEMORIES, instructions: INSTRUCTIONS)
end

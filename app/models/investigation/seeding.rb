module Investigation::Seeding
  extend ActiveSupport::Concern

  # One seeder per subject type. A new kind of subject adds a class and a line here.
  SEEDERS = {
    "Incident" => "Investigation::IncidentSeed"
  }.freeze

  class UnknownSubject < StandardError; end

  # Stored once so every later turn reads one row and sees the same facts. A resumed run keeps
  # the facts it started from.
  def build_seed_pack!
    return seed_pack if seed_pack.present?

    update!(seed_pack: seeder.gather)
    seed_pack
  end

  private

  def seeder
    class_name = SEEDERS[subject_type]
    raise UnknownSubject, "No seeder for #{subject_type}" unless class_name

    class_name.constantize.new(self)
  end
end

module Investigation::Seeding
  extend ActiveSupport::Concern

  # One seeder per subject type. A new kind of subject adds a class and a line here.
  SEEDERS = {
    "Incident" => "Investigation::IncidentSeed"
  }.freeze

  class UnknownSubject < StandardError; end

  # Gathered once, so every turn and a resumed run read the same facts.
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

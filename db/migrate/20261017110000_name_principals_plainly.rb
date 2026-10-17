# Firefight's own investigator is Halon wherever a principal is named. A run's ledger rows said who started it as the
# machine label, such as "user:Alice", and now keep the name alone, as the rows written from here on do.
class NamePrincipalsPlainly < ActiveRecord::Migration[8.1]
  MACHINE_PREFIX = "^(user|agent|api_key|system_agent):".freeze

  def up
    execute "UPDATE system_agents SET name = 'Halon', updated_at = now() WHERE slug = 'investigator'"
    execute <<~SQL.squish
      UPDATE ability_invocations SET triggered_by_label = regexp_replace(triggered_by_label, '#{MACHINE_PREFIX}', '')
      WHERE triggered_by_label ~ '#{MACHINE_PREFIX}'
    SQL
  end

  def down
    execute "UPDATE system_agents SET name = 'Firefight Investigator', updated_at = now() WHERE slug = 'investigator'"
  end
end

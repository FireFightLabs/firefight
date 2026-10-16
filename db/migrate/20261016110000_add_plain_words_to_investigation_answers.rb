# The short answer a channel reads, beside the full one: what kind of answer it is, what is wrong, the fix and what
# could not be checked, each in a plain sentence, and each claim in a few plain words. A fix step gets a short name and
# a plain reason when it fails, and a fix remembers that its ending was told, so a retried fix tells its new ending.
class AddPlainWordsToInvestigationAnswers < ActiveRecord::Migration[8.1]
  def change
    add_column :investigation_findings, :answer_kind, :string
    add_column :investigation_findings, :what_is_wrong, :text
    add_column :investigation_findings, :suggested_fix, :text
    add_column :investigation_findings, :not_checked, :text
    add_column :investigation_evidence, :plain, :text
    add_column :investigation_remediation_steps, :title, :string
    add_column :investigation_remediation_steps, :failure, :string
    add_column :investigation_remediation_plans, :ending_told_at, :datetime

    # A fix that ended before this was told by its own message then, so it is never told a second time. A cancelled fix
    # whose step is still running ends when that step does, so it is left for that ending to be told.
    reversible do |direction|
      direction.up do
        execute <<~SQL.squish
          UPDATE investigation_remediation_plans SET ending_told_at = updated_at
          WHERE status IN ('applied', 'partly_applied')
             OR (status = 'cancelled' AND NOT EXISTS (
                   SELECT 1 FROM investigation_remediation_steps
                   WHERE investigation_remediation_steps.plan_id = investigation_remediation_plans.id
                     AND investigation_remediation_steps.status = 'running'))
        SQL
      end
    end
  end
end

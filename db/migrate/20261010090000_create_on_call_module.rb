class CreateOnCallModule < ActiveRecord::Migration[8.1]
  def change
    change_table :workspaces, bulk: true do |t|
      t.boolean :alert_investigations_enabled, null: false, default: false
      t.integer :alert_storm_ceiling_cents, null: false, default: 2_000
      t.boolean :on_call_paging_enabled, null: false, default: false
    end

    create_table :ability_unattended_rules, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.references :resource, type: :uuid, null: false, foreign_key: { to_table: :resource_map_resources, on_delete: :cascade }
      t.string :capability, null: false
      t.string :metric, null: false
      t.decimal :threshold, precision: 14, scale: 3, null: false
      t.integer :minutes, null: false, default: 10
      t.boolean :enabled, null: false, default: true
      t.references :created_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.timestamps
    end

    change_table :investigation_remediation_plans, bulk: true do |t|
      t.text :unattended_reading
      t.datetime :unattended_checked_at
    end

    change_table :investigation_remediation_steps, bulk: true do |t|
      t.references :resource, type: :uuid, foreign_key: { to_table: :resource_map_resources, on_delete: :nullify }
      t.references :applied_under_rule, type: :uuid, foreign_key: { to_table: :ability_unattended_rules, on_delete: :nullify }
    end

    change_table :investigation_findings, bulk: true do |t|
      t.references :page_member, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.datetime :paged_at
    end

    change_table :ability_approvals, bulk: true do |t|
      t.references :approved_under_rule, type: :uuid, foreign_key: { to_table: :ability_unattended_rules, on_delete: :nullify }
      t.boolean :on_call_may_approve, null: false, default: false
    end
  end
end

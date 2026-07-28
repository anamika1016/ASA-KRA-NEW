class CreateEmployeeSidebarAccesses < ActiveRecord::Migration[8.0]
  def change
    create_table :employee_sidebar_accesses do |t|
      t.references :employee_detail, null: false, foreign_key: true, index: { unique: true }
      t.boolean :achievement_form_active, null: false, default: true
      t.boolean :submitted_targets_active, null: false, default: true
      t.timestamps
    end
  end
end

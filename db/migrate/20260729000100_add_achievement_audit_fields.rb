class AddAchievementAuditFields < ActiveRecord::Migration[8.0]
  def change
    add_reference :achievements, :submitted_by, foreign_key: { to_table: :users }, index: true
    add_column :achievements, :submitted_at, :datetime
    add_reference :achievements, :l1_reviewed_by, foreign_key: { to_table: :users }, index: true
    add_column :achievements, :l1_reviewed_at, :datetime

    add_index :achievements, :submitted_at
    add_index :achievements, :l1_reviewed_at
  end
end

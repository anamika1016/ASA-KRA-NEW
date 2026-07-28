class AddReviewMenusToEmployeeSidebarAccesses < ActiveRecord::Migration[8.0]
  def change
    add_column :employee_sidebar_accesses, :observer_1_active, :boolean, null: false, default: true
    add_column :employee_sidebar_accesses, :observer_2_active, :boolean, null: false, default: true
    add_column :employee_sidebar_accesses, :observer_3_active, :boolean, null: false, default: true
    add_column :employee_sidebar_accesses, :observer_4_active, :boolean, null: false, default: true
    add_column :employee_sidebar_accesses, :l1_active, :boolean, null: false, default: true
    add_column :employee_sidebar_accesses, :quarterly_pli_active, :boolean, null: false, default: true
  end
end

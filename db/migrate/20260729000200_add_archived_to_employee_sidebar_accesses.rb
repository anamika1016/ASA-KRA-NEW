class AddArchivedToEmployeeSidebarAccesses < ActiveRecord::Migration[8.0]
  def change
    add_column :employee_sidebar_accesses, :archived_active, :boolean, null: false, default: false
  end
end

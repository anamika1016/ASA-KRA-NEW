class AddQuarterlyPliReportToEmployeeSidebarAccesses < ActiveRecord::Migration[8.0]
  def change
    add_column :employee_sidebar_accesses, :quarterly_pli_report_active, :boolean, null: false, default: true
  end
end

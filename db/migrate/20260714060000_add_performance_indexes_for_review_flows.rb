class AddPerformanceIndexesForReviewFlows < ActiveRecord::Migration[8.0]
  def change
    add_index :employee_details, :employee_code, if_not_exists: true
    add_index :employee_details, :employee_email, if_not_exists: true
    add_index :employee_details, :l1_code, if_not_exists: true
    add_index :sms_logs, [ :employee_detail_id, :quarter, :sent ], name: "index_sms_logs_on_employee_quarter_sent", if_not_exists: true
  end
end

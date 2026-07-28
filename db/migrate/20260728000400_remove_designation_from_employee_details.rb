class RemoveDesignationFromEmployeeDetails < ActiveRecord::Migration[8.0]
  def change
    remove_column :employee_details, :designation, :string if column_exists?(:employee_details, :designation)
  end
end

require "test_helper"

class DepartmentActivityEditTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  fixtures []

  setup do
    sign_in User.create!(email: "department-edit-test@example.com", password: "password123", role: "admin")
    @employee = EmployeeDetail.create!(employee_id: "edit-test", employee_name: "Edit Test", department: "Operations")
    @year = "2026-2027"
    @department = Department.create!(department_type: "Operations", employee_reference: @employee.employee_id, financial_year: @year)
    @activity = @department.activities.create!(activity_name: "Original", unit: "Count")
    @assignment = UserDetail.create!(department: @department, activity: @activity, employee_detail: @employee, financial_year: @year)
  end

  test "updates KRIs across departments and keeps added rows after reload" do
    other_department = Department.create!(department_type: "Other", employee_reference: @employee.employee_id, financial_year: @year)
    other_activity = other_department.activities.create!(activity_name: "Other original")
    UserDetail.create!(department: other_department, activity: other_activity, employee_detail: @employee, financial_year: @year)
    patch "/departments/#{@department.id}/update_employee_activity_data", params: {
      employee_reference: @employee.employee_id,
      department: { department_type: "Operations", financial_year: @year, activities_attributes: {
        "0" => { id: @activity.id, activity_name: "Updated", unit: "Count", annual_target_fy: "10" },
        "1" => { id: other_activity.id, activity_name: "Other updated" },
        "2" => { activity_name: "Added row", unit: "Count", annual_target_fy: "20" }
      } }
    }, as: :json
    assert_response :success
    assert response.parsed_body["success"]
    assert_equal "Updated", @activity.reload.activity_name
    assert_equal "Other updated", other_activity.reload.activity_name
    assert_equal @assignment.id, UserDetail.find_by!(activity: @activity, employee_detail: @employee).id
    get "/departments/#{@employee.employee_id}/edit_data", params: { employee_reference: @employee.employee_id, financial_year: @year }, as: :json
    assert_response :success
    assert_equal ["Added row", "Other updated", "Updated"], response.parsed_body["activities"].map { |row| row["activity_name"] }.sort
  end

  test "unknown activity rolls back edits instead of reporting success" do
    patch "/departments/#{@department.id}/update_employee_activity_data", params: {
      department: { department_type: "Operations", financial_year: @year, activities_attributes: {
        "0" => { id: @activity.id, activity_name: "Should roll back" },
        "1" => { id: -1, activity_name: "Unknown" }
      } }
    }, as: :json
    assert_response :unprocessable_entity
    assert_equal false, response.parsed_body["success"]
    assert_equal "Original", @activity.reload.activity_name
  end
end

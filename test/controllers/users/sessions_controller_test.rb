require "test_helper"

class Users::SessionsControllerTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  test "employee list user can log in with default password when legacy password is unusable" do
    employee = EmployeeDetail.create!(
      employee_id: "EMP-AUTO-001",
      employee_name: "Auto Employee",
      employee_email: "auto-employee@example.com",
      employee_code: "AUTO001"
    )
    user = employee.ensure_portal_user!
    user.update_columns(encrypted_password: "legacy-password", password_changed_at: nil)

    post user_session_path, params: {
      user: {
        employee_code: employee.employee_code,
        password: EmployeeDetail::DEFAULT_PORTAL_PASSWORD
      }
    }

    assert_redirected_to settings_path
    assert user.reload.valid_password?(EmployeeDetail::DEFAULT_PORTAL_PASSWORD)
    assert_nil user.password_changed_at
  end

  test "default password is rejected after employee changes password" do
    user = User.create!(
      email: "default-after-change@example.com",
      employee_code: "CHG001",
      role: "employee",
      password: EmployeeDetail::DEFAULT_PORTAL_PASSWORD,
      password_confirmation: EmployeeDetail::DEFAULT_PORTAL_PASSWORD
    )
    EmployeeDetail.create!(
      employee_id: "EMP-CHG-001",
      employee_name: "Changed Employee",
      employee_email: user.email,
      employee_code: user.employee_code
    )
    user.update!(password: "654321", password_confirmation: "654321")

    post user_session_path, params: {
      user: {
        employee_code: user.employee_code,
        password: EmployeeDetail::DEFAULT_PORTAL_PASSWORD
      }
    }

    assert_redirected_to new_user_session_path
    assert_equal "Incorrect password.", flash[:alert]
  end
end

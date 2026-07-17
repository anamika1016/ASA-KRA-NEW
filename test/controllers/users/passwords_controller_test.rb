require "test_helper"

class Users::PasswordsControllerTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  test "forgot password starts reset from employee code" do
    user = User.create!(
      email: "reset-by-code@example.com",
      employee_code: "RST001",
      role: "employee",
      password: EmployeeDetail::DEFAULT_PORTAL_PASSWORD,
      password_confirmation: EmployeeDetail::DEFAULT_PORTAL_PASSWORD
    )

    post user_password_path, params: { user: { employee_code: " RST001 " } }

    assert_redirected_to(/\/users\/password\/edit\?reset_password_token=/)
    assert user.reload.reset_password_token.present?
  end

  test "changed password works after logout and relogin" do
    user = User.create!(
      email: "changed-password@example.com",
      employee_code: "RST002",
      role: "employee",
      password: EmployeeDetail::DEFAULT_PORTAL_PASSWORD,
      password_confirmation: EmployeeDetail::DEFAULT_PORTAL_PASSWORD
    )

    post user_password_path, params: { user: { employee_code: user.employee_code } }
    token = response.location.split("reset_password_token=").last

    put user_password_path, params: {
      user: {
        reset_password_token: token,
        password: "654321",
        password_confirmation: "654321"
      }
    }

    assert user.reload.valid_password?("654321")
    assert user.password_changed_at.present?

    delete destroy_user_session_path
    post user_session_path, params: { user: { employee_code: user.employee_code, password: "654321" } }

    assert_redirected_to settings_path
  end

  test "unknown employee code does not start reset" do
    post user_password_path, params: { user: { employee_code: "UNKNOWN" } }

    assert_response :success
    assert_equal "Employee code not found", flash[:alert]
  end
end

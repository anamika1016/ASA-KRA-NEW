require "test_helper"

class UserDetailsControllerTest < ActionDispatch::IntegrationTest
  test "removed observer approvals do not keep achievement month locked" do
    employee = EmployeeDetail.create!(employee_id: SecureRandom.uuid, employee_name: "Dynamic Observer Test")
    ObserverPliReview.create!(
      employee_detail: employee,
      financial_year: "2026-2027",
      quarter: "Q1",
      month: "april",
      observer_level: "obs_code1",
      status: "approved"
    )

    assert_not UserDetailsController.new.send(
      :observer_approval_locks_month?,
      employee.id,
      "2026-2027",
      "april"
    )
  end

  test "observer SMS duplicate check follows the currently mapped recipient" do
    employee = EmployeeDetail.create!(employee_id: SecureRandom.uuid, employee_name: "SMS Employee")
    old_observer = EmployeeDetail.create!(employee_id: SecureRandom.uuid, employee_name: "Old Observer")
    new_observer = EmployeeDetail.create!(employee_id: SecureRandom.uuid, employee_name: "New Observer")
    SmsLog.create!(
      employee_detail: employee,
      quarter: "Q1",
      month: "april",
      recipient_role: "observer",
      recipient_employee_detail_id: old_observer.id,
      observer_level: "obs_code1",
      sent: true
    )
    controller = UserDetailsController.new

    assert controller.send(:observer_sms_already_sent?, employee.id, "Q1", "april", "obs_code1", old_observer.id)
    assert_not controller.send(:observer_sms_already_sent?, employee.id, "Q1", "april", "obs_code1", new_observer.id)
  end

  test "should get new" do
    get user_details_new_url
    assert_response :success
  end

  test "should get show" do
    get user_details_show_url
    assert_response :success
  end

  test "should get index" do
    get user_details_index_url
    assert_response :success
  end
end

require "test_helper"
require "minitest/mock"

# End-to-end checks of who gets an SMS and who gets a krai mail at each KRA step.
# SMS gateway is stubbed; mails are only queued (KraMailJob), never sent.
class KraMailFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  self.fixture_table_names = []

  FY = "2026-2027".freeze
  QUARTER_LABEL = "Q1 (APR-JUN)".freeze

  setup do
    # Rails 8 loads routes lazily; Devise needs them for sign_in.
    Rails.application.try(:reload_routes_unless_loaded)
    @previous_relay = ENV["KRA_MAIL_RELAY_URL"]
    ENV["KRA_MAIL_RELAY_URL"] = "https://krai.asaindia.org/asakra_notification.aspx"
    @sms = []

    @l1 = EmployeeDetail.create!(employee_id: SecureRandom.uuid, employee_name: "Ramesh Kumar", employee_code: "KM1",
                                 employee_email: "ramesh.kra@example.com", mobile_number: "9876500001")
    @observer = EmployeeDetail.create!(employee_id: SecureRandom.uuid, employee_name: "Sunita Sharma", employee_code: "KO1",
                                       employee_email: "sunita.kra@example.com", mobile_number: "9876500002")
    @employee = EmployeeDetail.create!(employee_id: SecureRandom.uuid, employee_name: "Asha Devi", employee_code: "KE1",
                                       employee_email: "asha.kra@example.com", mobile_number: "9876500003", l1_code: "KM1")

    @hod_detail = EmployeeDetail.create!(employee_id: SecureRandom.uuid, employee_name: "Head Of Dept", employee_code: "KH1",
                                         employee_email: "hod.kra@example.com")
    @hod = User.find_by(email: "hod.kra@example.com") ||
           User.create!(email: "hod.kra@example.com", password: "Password@123", employee_code: "KH1")
    @hod.update!(role: "hod")
  end

  teardown do
    ENV["KRA_MAIL_RELAY_URL"] = @previous_relay
  end

  # ---- submission -------------------------------------------------------

  test "submission without observers: L1 gets SMS and mail" do
    result = with_sms { notify_after_submission(@employee) }

    assert result[:success], result.inspect
    assert_equal [ "9876500001" ], @sms.map(&:first)
    assert_equal [ [ "kra_submitted_to_l1", "ramesh.kra@example.com" ], [ "employee_submitted", "asha.kra@example.com" ] ], queued_mails
    assert SmsLog.exists?(employee_detail_id: @employee.id, recipient_role: "l1", sent: true)

    employee_mail = queued_params.last
    assert_equal "Your KRA MIS April submitted", employee_mail["subject"]
    assert_equal "Your KRA MIS for April has been submitted successfully and sent to L1 - Ramesh Kumar for review.", employee_mail["message"]
    assert_equal "Asha Devi", employee_mail["to_name"]
  end

  test "submission with observers: every observer gets SMS and mail, L1 nothing" do
    @employee.update!(obs_code1: "KO1")

    result = with_sms { notify_after_submission(@employee) }

    assert result[:success], result.inspect
    assert_equal [ "9876500002" ], @sms.map(&:first)
    assert_equal [ [ "kra_submitted_to_observer", "sunita.kra@example.com" ], [ "employee_submitted", "asha.kra@example.com" ] ], queued_mails
    assert_equal "OB1", queued_params.first["reviewer_role"]
    assert_equal "Your KRA MIS for April has been submitted successfully and sent to OB1 - Sunita Sharma for review.", queued_params.last["message"]
    assert_not SmsLog.exists?(employee_detail_id: @employee.id, recipient_role: "l1")
  end

  test "submission when L1 has no mobile: mail still goes, a resubmission mails as an update" do
    @l1.update!(mobile_number: nil)

    result = with_sms { notify_after_submission(@employee) }
    assert result[:success], result.inspect
    assert result.dig(:l1_result, :mail_only)
    assert_empty @sms
    assert_equal [ [ "kra_submitted_to_l1", "ramesh.kra@example.com" ], [ "employee_submitted", "asha.kra@example.com" ] ], queued_mails

    clear_enqueued_jobs
    with_sms { notify_after_submission(@employee) }
    assert_equal [ [ "kra_updated_to_l1", "ramesh.kra@example.com" ], [ "employee_submitted", "asha.kra@example.com" ] ], queued_mails
  end

  test "with the relay off nothing changes: no mail, missing mobile still fails" do
    ENV["KRA_MAIL_RELAY_URL"] = nil
    @l1.update!(mobile_number: nil)

    result = with_sms { notify_after_submission(@employee) }

    assert_not result[:success]
    assert_equal "L1 manager mobile number not found", result[:error]
    assert_empty queued_mails
    assert_not SmsLog.exists?(employee_detail_id: @employee.id)
  end

  # ---- the real submit button (Achievement Form) --------------------------

  test "submit then edit and submit again: L1 gets SMS once, mail both times" do
    detail = month_target(@employee)
    sign_in employee_user

    with_sms { submit_month(detail, "8") }
    assert_redirected_or_ok
    assert_equal [ "9876500001" ], @sms.map(&:first)
    assert_equal [ [ "kra_submitted_to_l1", "ramesh.kra@example.com" ], [ "employee_submitted", "asha.kra@example.com" ] ], queued_mails

    clear_enqueued_jobs
    @sms.clear
    with_sms { submit_month(detail, "9") }
    assert_redirected_or_ok
    assert_empty @sms, "SMS goes only once per month"
    assert_equal [ [ "kra_updated_to_l1", "ramesh.kra@example.com" ], [ "employee_submitted", "asha.kra@example.com" ] ], queued_mails
    mail = queued_params.first
    assert_equal "KRA MIS updated - Asha Devi (April)", mail["subject"]
    assert_equal "April", mail["month"]
  end

  test "edit and submit again with observers: observer gets mail again, L1 nothing" do
    @employee.update!(obs_code1: "KO1")
    detail = month_target(@employee)
    sign_in employee_user

    with_sms { submit_month(detail, "8") }
    assert_equal [ [ "kra_submitted_to_observer", "sunita.kra@example.com" ], [ "employee_submitted", "asha.kra@example.com" ] ], queued_mails

    clear_enqueued_jobs
    @sms.clear
    with_sms { submit_month(detail, "9") }
    assert_empty @sms
    assert_equal [ [ "kra_updated_to_observer", "sunita.kra@example.com" ], [ "employee_submitted", "asha.kra@example.com" ] ], queued_mails
  end

  test "observers approve again after an edit: L1 gets the mail without a second SMS" do
    @employee.update!(obs_code1: "KO1")
    submitted_month_data(@employee)
    SmsLog.create!(employee_detail: @employee, quarter: QUARTER_LABEL, month: "april", recipient_role: "l1",
                   recipient_employee_detail_id: @l1.id, sent: true, sent_at: Time.current)
    sign_in @hod

    with_sms do
      post save_observer_pli_employee_details_path, params: observer_params("approve", "Ok again")
    end

    assert_nil flash[:alert]
    assert_empty @sms
    assert_includes queued_mails, [ "kra_observers_approved_to_l1", "ramesh.kra@example.com" ]
  end

  # ---- observer decision ------------------------------------------------

  test "observer approves: employee gets mail, then L1 gets SMS and mail" do
    @employee.update!(obs_code1: "KO1")
    submitted_month_data(@employee)
    sign_in @hod

    with_sms do
      post save_observer_pli_employee_details_path, params: observer_params("approve", "Looks fine")
    end

    assert_response :redirect
    assert_nil flash[:alert]
    assert_includes queued_mails, [ "employee_observer_approved", "asha.kra@example.com" ]
    assert_includes queued_mails, [ "kra_observers_approved_to_l1", "ramesh.kra@example.com" ]
    assert_equal [ "9876500001" ], @sms.map(&:first)
    l1_mail = queued_params.find { |p| p["mail_type"] == "kra_observers_approved_to_l1" }
    assert_equal "Ramesh Kumar", l1_mail["to_name"]
    assert_equal "KRA MIS ready for L1 review - Asha Devi (April)", l1_mail["subject"]
    assert_equal "All observers have approved the KRA MIS of Asha Devi for April. It is now waiting for your L1 review.", l1_mail["message"]

    employee_mail = queued_params.find { |p| p["mail_type"] == "employee_observer_approved" }
    assert_equal "OB1", employee_mail["reviewer_role"]
    assert_equal "Head Of Dept", employee_mail["reviewer_name"]
    assert_equal "Looks fine", employee_mail["remarks"]
    assert_equal "April", employee_mail["month"]
  end

  test "observer returns: employee gets mail, L1 nothing" do
    @employee.update!(obs_code1: "KO1")
    submitted_month_data(@employee)
    sign_in @hod

    with_sms do
      post save_observer_pli_employee_details_path, params: observer_params("return", "Add proof")
    end

    assert_response :redirect
    assert_nil flash[:alert]
    assert_equal [ [ "employee_observer_returned", "asha.kra@example.com" ] ], queued_mails
    assert_empty @sms
  end

  # ---- L1 / L2 decision -------------------------------------------------

  test "L1 approves: employee gets mail with who approved" do
    submitted_month_data(@employee)
    sign_in @hod

    patch approve_employee_detail_path(@employee), params: review_params("Good work"), xhr: true

    assert_response :success
    assert JSON.parse(response.body)["success"], response.body
    assert_equal [ [ "employee_l1_approved", "asha.kra@example.com" ] ], queued_mails
    mail = queued_params.first
    assert_equal "L1", mail["reviewer_role"]
    assert_equal "Head Of Dept", mail["reviewer_name"]
    assert_equal "Good work", mail["remarks"]
    assert_equal "approved", mail["action"]
  end

  test "L1 returns: employee gets returned mail" do
    submitted_month_data(@employee)
    sign_in @hod

    patch return_employee_detail_path(@employee), params: review_params("Fix it"), xhr: true

    assert_response :success
    assert JSON.parse(response.body)["success"], response.body
    assert_equal [ [ "employee_l1_returned", "asha.kra@example.com" ] ], queued_mails
  end

  test "L2 is switched off in the app, so it sends no mail" do
    @employee.update!(l2_code: "KH1")
    submitted_month_data(@employee, status: "l1_approved")
    sign_in @hod

    patch l2_approve_employee_detail_path(@employee), params: review_params("L2 ok"), xhr: true

    assert_response :unprocessable_entity
    assert_empty queued_mails
  end

  test "Quarterly PLI approved and returned: employee gets mail each time" do
    submitted_month_data(@employee, status: "l1_approved")
    sign_in @hod

    post save_quarterly_pli_employee_details_path,
         params: { financial_year: FY, quarter: "Q1", employee_detail_id: @employee.id, final_percentage: "85",
                   final_remarks: "Well done", action_type: "approve" }
    assert_response :redirect
    assert_nil flash[:alert]
    assert_equal [ [ "employee_pli_approved", "asha.kra@example.com" ] ], queued_mails
    mail = queued_params.first
    assert_equal "PLI", mail["reviewer_role"]
    assert_equal "Head Of Dept", mail["reviewer_name"]
    assert_equal "", mail["month"]
    assert_equal "Q1 (APR-JUN)", mail["quarter"]

    clear_enqueued_jobs
    post save_quarterly_pli_employee_details_path,
         params: { financial_year: FY, quarter: "Q1", employee_detail_id: @employee.id,
                   final_remarks: "Recheck", action_type: "return" }
    assert_response :redirect
    assert_nil flash[:alert]
    assert_equal [ [ "employee_pli_returned", "asha.kra@example.com" ] ], queued_mails
  end

  test "L1 approve still works with the relay off and sends no mail" do
    ENV["KRA_MAIL_RELAY_URL"] = nil
    submitted_month_data(@employee)
    sign_in @hod

    patch approve_employee_detail_path(@employee), params: review_params("Good work"), xhr: true

    assert_response :success
    assert JSON.parse(response.body)["success"], response.body
    assert_empty queued_mails
  end

  test "a broken mail never breaks the L1 approve" do
    submitted_month_data(@employee)
    sign_in @hod

    KraMailRelay.stub(:notify_employee, ->(*) { raise "krai down" }) do
      patch approve_employee_detail_path(@employee), params: review_params("Good work"), xhr: true
    end

    assert_response :success
    assert JSON.parse(response.body)["success"], response.body
  end

  private

  def with_sms
    sender = lambda do |mobile, message, **|
      @sms << [ mobile, message ]
      { success: true, message: "SMS sent successfully" }
    end
    SmsNotificationService.stub(:send_message, sender) { yield }
  end

  def notify_after_submission(employee)
    UserDetailsController.new.send(:notify_reviewers_after_submission, employee, QUARTER_LABEL, "april", nil)
  end

  def queued_mails
    queued_params.map { |params| [ params["mail_type"], params["to_email"] ] }
  end

  def queued_params
    enqueued_jobs.select { |job| job["job_class"] == "KraMailJob" || job[:job] == KraMailJob }
                 .map { |job| job[:args].last }
  end

  def submitted_month_data(employee, status: "pending")
    department = Department.create!(department_type: "KRA Mail Dept", financial_year: FY, employee_reference: employee.employee_code)
    activity = Activity.create!(department: department, activity_name: "KRA Mail Activity", unit: "Nos", weight: 10)
    detail = UserDetail.find_or_create_by!(employee_detail: employee, department: department, activity: activity, financial_year: FY) do |record|
      record.april = "10"
    end
    detail.update!(april: "10")
    Achievement.create!(user_detail: detail, month: "april", achievement: "8", employee_remarks: "Done", status: status)
  end

  def month_target(employee)
    department = Department.create!(department_type: "KRA Mail Dept", financial_year: FY, employee_reference: employee.employee_code)
    activity = Activity.create!(department: department, activity_name: "KRA Mail Activity", unit: "Nos", weight: 10)
    detail = UserDetail.find_or_create_by!(employee_detail: employee, department: department, activity: activity, financial_year: FY)
    detail.update!(april: "10")
    detail
  end

  def employee_user
    user = User.find_by(email: @employee.employee_email) ||
           User.create!(email: @employee.employee_email, password: "Password@123", employee_code: @employee.employee_code)
    user.update!(role: "employee")
    @employee.update_column(:user_id, user.id)
    user
  end

  def submit_month(detail, value)
    post submit_achievements_user_details_path,
         params: { month: "april", financial_year: FY,
                   achievement: { detail.id.to_s => { "april" => { achievement: value, employee_remarks: "Done" } } } }
  end

  def assert_redirected_or_ok
    assert_includes [ 200, 302 ], response.status, response.body.first(300)
    assert_nil flash[:alert], flash[:alert]
  end

  def observer_params(action_type, remarks)
    { observer_level: "obs_code1", financial_year: FY, quarter: "Q1", month: "april",
      employee_detail_id: @employee.id, final_remarks: remarks, action_type: action_type }
  end

  def review_params(remarks)
    { selected_month: "april", selected_quarter: "Q1", financial_year: FY, remarks: remarks }
  end
end

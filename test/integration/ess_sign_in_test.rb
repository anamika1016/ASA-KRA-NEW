require "test_helper"

# ESS → IT Tools → ASA KRA: a signed, short-lived link signs the employee in without a password.
class EssSignInTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    Rails.application.try(:reload_routes_unless_loaded)
    @old = ENV["ESS_SSO_SECRET"]
    ENV["ESS_SSO_SECRET"] = "ess-test-secret"
    @emp = EmployeeDetail.create!(employee_id: SecureRandom.uuid, employee_name: "Asha Devi", employee_code: "ESS1",
                                  employee_email: "asha.ess@example.com", mobile_number: "9876500101")
  end

  teardown { ENV["ESS_SSO_SECRET"] = @old }

  def link(code, expires_at: 2.minutes.from_now.to_i, secret: "ess-test-secret")
    sig = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{code}:#{expires_at}")
    ess_sign_in_path(code, expires_at: expires_at, signature: sig)
  end

  test "a correctly signed link signs the employee in" do
    get link("ESS1")
    assert_response :redirect
    follow_redirect!
    assert_not_equal new_user_session_path, path
    assert controller.user_signed_in?
    assert_equal "ESS1", controller.current_user.employee_code
  end

  test "wrong signature, expired or far-future link is refused" do
    [ link("ESS1", secret: "other"), link("ESS1", expires_at: 1.minute.ago.to_i), link("ESS1", expires_at: 1.day.from_now.to_i),
      ess_sign_in_path("ESS1") ].each do |url|
      get url
      assert_redirected_to new_user_session_path
      follow_redirect!
      assert_not controller.user_signed_in?
    end
  end

  test "no secret configured means no sign-in" do
    ENV["ESS_SSO_SECRET"] = nil
    get link("ESS1")
    assert_redirected_to new_user_session_path
  end
end

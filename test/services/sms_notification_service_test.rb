require "test_helper"

class SmsNotificationServiceTest < ActiveSupport::TestCase
  Response = Struct.new(:body, :code) do
    def success?
      true
    end
  end

  test "send_sms sends ASA gateway parameters" do
    captured_url = nil
    captured_options = nil
    response = Response.new(%({"Status":"Success","Code":"000","Message-Id":"MSG123","Description":"Submitted"}), 200)

    HTTParty.stub(:get, ->(url, options) {
      captured_url = url
      captured_options = options
      response
    }) do
      result = SmsNotificationService.send_sms("917723879227", SmsNotificationService.submission_message("Test User", "Q1 (APR-JUN)"))

      assert result[:success]
      assert_equal "MSG123", result[:message_id]
    end

    assert_equal SmsNotificationService::API_URL, captured_url
    assert_equal "3230666f72736131353261", captured_options[:query][:authkey]
    assert_equal "ACTFSA", captured_options[:query][:sender]
    assert_equal "1707175983185179621", captured_options[:query][:DLT_TE_ID]
    assert_equal "917723879227", captured_options[:query][:mobiles]
    assert_equal 30, captured_options[:timeout]
  end

  test "send_message keeps old controller failure shape" do
    result = SmsNotificationService.send_message("12345", "Hello")

    assert_not result[:success]
    assert_equal "Invalid mobile number format", result[:message]
    assert_equal "Invalid mobile number format", result[:error]
  end

  test "submission_message uses compact quarter for DLT matching" do
    assert_equal(
      "Emp-Name: Test User has submitted his first Quarter KRA MIS. Please review and approve in the system. Action For Social Advancement (ASA)",
      SmsNotificationService.submission_message("Test User", "Q1 (APR-JUN)")
    )
  end
end

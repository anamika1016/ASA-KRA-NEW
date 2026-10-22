require "test_helper"
require "minitest/mock"

# KRA SMS notifications are also emailed through krai, one page per kind,
# but only once KRA_MAIL_RELAY_URL is set.
class KraMailRelayTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  self.fixture_table_names = []

  Person = Struct.new(:employee_name, :employee_email, :employee_code, keyword_init: true)

  FakeResponse = Struct.new(:code, :body, :message, :success) do
    def is_a?(klass)
      klass == Net::HTTPSuccess ? success : super
    end

    def [](_header)
      nil
    end
  end

  setup do
    @employee = Person.new(employee_name: "Asha Devi", employee_code: "E-101", employee_email: "asha@example.com")
    @l1 = Person.new(employee_name: "L1 Manager", employee_code: "M-1", employee_email: "l1.manager@example.com")
  end

  test "nothing is queued while the relay address is not set" do
    with_env("KRA_MAIL_RELAY_URL" => nil) do
      assert_no_enqueued_jobs(only: KraMailJob) { notify }
    end
  end

  test "nothing is queued when the recipient has no email" do
    @l1.employee_email = ""
    with_env("KRA_MAIL_RELAY_URL" => "https://krai.asaindia.org/") do
      assert_no_enqueued_jobs(only: KraMailJob) { notify }
    end
  end

  test "one mail is queued when the relay is on" do
    with_env("KRA_MAIL_RELAY_URL" => "https://krai.asaindia.org/") do
      assert_enqueued_with(job: KraMailJob) { assert notify }
    end
  end

  test "each kind goes to its own krai page and carries the details" do
    called = nil
    fake = ->(uri) { called = uri; FakeResponse.new("200", "Email sent", "OK", true) }

    with_env("KRA_MAIL_RELAY_URL" => "https://krai.asaindia.org/", "KRA_MAIL_APP_URL" => "https://asakra.asaindia.org") do
      params = KraMailRelay.params_for("kra_submitted_to_observer", recipient: @l1, employee_detail: @employee,
                                                                     quarter: "Q1 (APR-JUN)", message: "Hello", month: "july", reviewer_role: "OB2")
      KraMailRelay.stub(:get, fake) { assert KraMailRelay.deliver!("kra_submitted_to_observer", params) }
    end

    assert_equal "/asakra_submitted_to_observer.aspx", called.path
    query = URI.decode_www_form(called.query).to_h
    assert_equal KraMailRelay::FIELDS, query.keys
    assert_equal "l1.manager@example.com", query["to_email"]
    assert_equal "L1 Manager", query["to_name"]
    assert_equal "KRA MIS submitted for observer review - Asha Devi (July)", query["subject"]
    assert_equal "Asha Devi has submitted the KRA MIS for July. Please review and approve in the system.", query["message"]
    assert_equal "July", query["month"]
    assert_equal "https://asakra.asaindia.org/employee_details/observer_2", query["link"]
    assert_equal "E-101", query["employee_code"]
    assert_equal "OB2", query["reviewer_role"]
  end

  test "one krai page for every kind" do
    with_env("KRA_MAIL_RELAY_URL" => "https://krai.asaindia.org/asakra_notification.aspx") do
      assert_equal "https://krai.asaindia.org/asakra_notification.aspx", KraMailRelay.page_url("kra_submitted_to_l1")
      assert_equal "https://krai.asaindia.org/asakra_notification.aspx", KraMailRelay.page_url("employee_pli_returned")
    end
  end

  test "a page can be renamed per kind" do
    with_env("KRA_MAIL_RELAY_URL" => "https://krai.asaindia.org", "KRA_MAIL_PAGE_KRA_SUBMITTED_TO_L1" => "nKra.aspx") do
      assert_equal "https://krai.asaindia.org/nKra.aspx", KraMailRelay.page_url("kra_submitted_to_l1")
      assert_equal "https://krai.asaindia.org/asakra_observers_approved_to_l1.aspx", KraMailRelay.page_url("kra_observers_approved_to_l1")
    end
  end

  test "krai refusing with 200 counts as a failure" do
    refused = ->(_uri) { FakeResponse.new("200", "<html><style>body{}</style><div>KRA Email Notification Invalid KRA action.</div></html>", "OK", true) }
    sent = ->(_uri) { FakeResponse.new("200", "<html><div>Email sent successfully to l1.manager@example.com</div><p>Remarks: target failed</p></html>", "OK", true) }
    params = { "to_email" => "l1.manager@example.com" }

    with_env("KRA_MAIL_RELAY_URL" => "https://krai.asaindia.org/asakra_notification.aspx") do
      error = KraMailRelay.stub(:get, refused) do
        assert_raises(KraMailRelay::DeliveryError) { KraMailRelay.deliver!("kra_submitted_to_l1", params) }
      end
      assert_includes error.message, "Invalid KRA action."
      KraMailRelay.stub(:get, sent) { assert KraMailRelay.deliver!("kra_submitted_to_l1", params) }
    end
  end

  test "action words are the ones krai accepts" do
    assert_equal "pending", KraMailRelay.action_for("kra_submitted_to_l1")
    assert_equal "pending", KraMailRelay.action_for("kra_updated_to_observer")
    assert_equal "approved", KraMailRelay.action_for("employee_l1_approved")
    assert_equal "rejected", KraMailRelay.action_for("employee_observer_returned")
  end

  test "a failing mail service never breaks the job" do
    fake = ->(_uri) { FakeResponse.new("404", "The resource cannot be found.", "Not Found", false) }

    with_env("KRA_MAIL_RELAY_URL" => "https://krai.asaindia.org/") do
      KraMailRelay.stub(:get, fake) do
        assert_nothing_raised { KraMailJob.perform_now("kra_submitted_to_l1", { "to_email" => "l1.manager@example.com" }) }
      end
    end
  end

  test "a queued mail counts as informed when the SMS could not go" do
    sms_failed = { success: false, error: "L1 manager mobile number not found" }

    result = KraMailRelay.with_mail(sms_failed, true)
    assert result[:success]
    assert result[:mail_only]
    assert_equal "Email sent; SMS not sent (L1 manager mobile number not found)", result[:message]

    assert_equal sms_failed, KraMailRelay.with_mail(sms_failed, false)
    assert_equal({ success: true, message: "SMS sent" }, KraMailRelay.with_mail({ success: true, message: "SMS sent" }, true))
  end

  test "the employee hears who approved or returned their KRA MIS" do
    called = nil
    fake = ->(uri) { called = uri; FakeResponse.new("200", "OK", "OK", true) }

    with_env("KRA_MAIL_RELAY_URL" => "https://krai.asaindia.org/", "KRA_MAIL_APP_URL" => "https://asakra.asaindia.org") do
      queued = nil
      assert_enqueued_with(job: KraMailJob) do
        queued = KraMailRelay.notify_employee("employee_l1_returned", employee_detail: @employee, quarter: "Q1 (APR-JUN)", month: "april",
                                                                      reviewer_role: "L1", reviewer_name: "L1 Manager", remarks: "Add proof")
      end
      assert queued
      kind, params = enqueued_jobs.last[:args]
      KraMailRelay.stub(:get, fake) { assert KraMailRelay.deliver!(kind, params) }
    end

    assert_equal "/asakra_employee_l1_returned.aspx", called.path
    query = URI.decode_www_form(called.query).to_h
    assert_equal KraMailRelay::FIELDS, query.keys
    assert_equal "asha@example.com", query["to_email"]
    assert_equal "Your KRA MIS April returned by L1 L1 Manager", query["subject"]
    assert_equal "Your KRA MIS for April has been returned by L1 L1 Manager. Please check and resubmit. Remarks: Add proof", query["message"]
    assert_equal "https://asakra.asaindia.org/user_details/get_user_detail", query["link"]
    assert_equal "April", query["month"]
    assert_equal "rejected", query["action"]
    assert_equal "L1 Manager", query["reviewer_name"]
    assert_equal "Add proof", query["remarks"]
    assert_equal "employee_l1_returned", query["mail_type"]
  end

  private

  def notify
    KraMailRelay.notify("kra_submitted_to_l1", recipient: @l1, employee_detail: @employee, quarter: "Q1 (APR-JUN)", message: "Hello")
  end

  def with_env(values)
    previous = values.keys.to_h { |key| [ key, ENV[key] ] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end

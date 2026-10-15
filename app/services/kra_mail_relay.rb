require "json"
require "net/http"
require "uri"

# Sends an email copy of every KRA SMS notification through krai (the server
# has no working SMTP), the same way Apurti sends its notification mails. Krai
# has one page per kind of mail:
#
#   GET https://krai.asaindia.org/<page>?to_email=...&to_name=...&subject=...&message=...&link=...
#       &employee_name=...&employee_code=...&quarter=...&month=...&reviewer_role=...
#       &reviewer_name=...&action=...&remarks=...&mail_type=<kind>
#
# Reviewers get a mail with each submission SMS; the employee gets one for
# every approve or return at any level (observer, L1, L2, Quarterly PLI).
#
# KRA_MAIL_RELAY_URL is krai's address (https://krai.asaindia.org/). A page krai
# names differently is set with KRA_MAIL_PAGE_<KIND>, e.g.
# KRA_MAIL_PAGE_KRA_SUBMITTED_TO_L1=nKraSubmitted.aspx. If the relay URL itself
# is a page (…/x.aspx), every kind without its own page goes there; krai's one
# page (asakra_notification.aspx) tells the kinds apart by mail_type.
#
# Off until KRA_MAIL_RELAY_URL is set, so nothing changes before krai provides
# the pages. A failed mail never affects the SMS or the action that sent it.
class KraMailRelay
  class DeliveryError < StandardError; end

  FIELDS = %w[
    to_email to_name subject message link employee_name employee_code quarter month
    reviewer_role reviewer_name action remarks mail_type
  ].freeze

  # kind => krai page
  PAGES = {
    "kra_submitted_to_l1" => "asakra_submitted_to_l1.aspx",
    "kra_submitted_to_observer" => "asakra_submitted_to_observer.aspx",
    "kra_observers_approved_to_l1" => "asakra_observers_approved_to_l1.aspx",
    "kra_updated_to_l1" => "asakra_updated_to_l1.aspx",
    "kra_updated_to_observer" => "asakra_updated_to_observer.aspx",
    "employee_observer_approved" => "asakra_employee_observer_approved.aspx",
    "employee_observer_returned" => "asakra_employee_observer_returned.aspx",
    "employee_l1_approved" => "asakra_employee_l1_approved.aspx",
    "employee_l1_returned" => "asakra_employee_l1_returned.aspx",
    "employee_l2_approved" => "asakra_employee_l2_approved.aspx",
    "employee_l2_returned" => "asakra_employee_l2_returned.aspx",
    "employee_pli_approved" => "asakra_employee_pli_approved.aspx",
    "employee_pli_returned" => "asakra_employee_pli_returned.aspx"
  }.freeze
  DEFAULT_PAGE = "asakra_notification.aspx".freeze

  SUBJECTS = {
    "kra_submitted_to_l1" => "KRA MIS submitted - %{employee_name} (%{quarter})",
    "kra_submitted_to_observer" => "KRA MIS submitted for observer review - %{employee_name} (%{quarter})",
    "kra_observers_approved_to_l1" => "KRA MIS ready for L1 review - %{employee_name} (%{quarter})",
    "kra_updated_to_l1" => "KRA MIS updated - %{employee_name} (%{period})",
    "kra_updated_to_observer" => "KRA MIS updated for observer review - %{employee_name} (%{period})",
    "employee_observer_approved" => "Your KRA MIS %{period} approved by %{reviewer_role} %{reviewer_name}",
    "employee_observer_returned" => "Your KRA MIS %{period} returned by %{reviewer_role} %{reviewer_name}",
    "employee_l1_approved" => "Your KRA MIS %{period} approved by L1 %{reviewer_name}",
    "employee_l1_returned" => "Your KRA MIS %{period} returned by L1 %{reviewer_name}",
    "employee_l2_approved" => "Your KRA MIS %{period} approved by L2 %{reviewer_name}",
    "employee_l2_returned" => "Your KRA MIS %{period} returned by L2 %{reviewer_name}",
    "employee_pli_approved" => "Your Quarterly PLI %{period} approved by %{reviewer_name}",
    "employee_pli_returned" => "Your Quarterly PLI %{period} returned by %{reviewer_name}"
  }.freeze

  KRAI_SENT = /email sent successfully/i
  KRAI_REFUSED = /invalid|missing|not sent|failed|error/i
  DEFAULT_APP_URL = "https://asakra.asaindia.org".freeze
  TIMEOUT_SECONDS = 15
  MAX_REDIRECTS = 3

  def self.url
    ENV["KRA_MAIL_RELAY_URL"].to_s.strip
  end

  def self.enabled?
    url.present?
  end

  # Queues one mail; never raises, so callers can fire and forget next to the SMS.
  def self.notify(kind, recipient:, employee_detail:, quarter:, message:, **details)
    return false unless enabled?

    params = params_for(kind, recipient: recipient, employee_detail: employee_detail, quarter: quarter,
                              message: message, **details)
    return false unless params["to_email"].include?("@")

    KraMailJob.perform_later(kind.to_s, params)
    true
  rescue StandardError => error
    Rails.logger.error("KraMailRelay could not queue kind=#{kind}: #{error.class} #{error.message}")
    false
  end

  # The mail goes even when the SMS cannot (no mobile number, gateway error);
  # a queued mail then counts as the reviewer being informed, so it is logged
  # once like a sent SMS and not repeated on the next submission.
  def self.with_mail(sms_result, mail_queued)
    return sms_result if sms_result[:success] || !mail_queued

    sms_result.merge(success: true, mail_only: true, message: "Email sent; SMS not sent (#{sms_result[:error]})")
  end

  # The employee edited and submitted a month again. The SMS goes only once per
  # month, but the reviewer gets a mail every time.
  def self.notify_update(kind, recipient:, employee_detail:, quarter:, month: nil, reviewer_role: nil)
    message = "#{employee_detail.employee_name} has updated the KRA MIS for #{period_for(quarter, month)}. " \
              "Please review and approve in the system. Action For Social Advancement (ASA)"
    notify(kind, recipient: recipient, employee_detail: employee_detail, quarter: quarter, message: message,
                 month: month, reviewer_role: reviewer_role)
  end

  # Tells the employee who approved or returned their KRA MIS. kind is
  # employee_<observer|l1|l2|pli>_<approved|returned>; reviewer_role is
  # OB1-OB4, L1, L2 or PLI.
  def self.notify_employee(kind, employee_detail:, quarter:, reviewer_role:, reviewer_name:, month: nil, remarks: nil)
    action = kind.to_s.end_with?("_returned") ? "returned" : "approved"
    what = kind.to_s.start_with?("employee_pli_") ? "Quarterly PLI" : "KRA MIS"
    by = [ reviewer_role == "PLI" ? nil : reviewer_role, reviewer_name.presence ].compact.join(" ")
    message = "Dear #{employee_detail.employee_name}, your #{what} for #{period_for(quarter, month)} has been #{action} by #{by}."
    message += " Please check and resubmit." if action == "returned"
    message += " Remarks: #{remarks}" if remarks.present?

    notify(kind, recipient: employee_detail, employee_detail: employee_detail, quarter: quarter, message: message,
                 month: month, reviewer_role: reviewer_role, reviewer_name: reviewer_name, remarks: remarks)
  end

  def self.params_for(kind, recipient:, employee_detail:, quarter:, message:, reviewer_role: nil, month: nil, reviewer_name: nil, remarks: nil)
    reviewer_role = reviewer_role.presence || "L1"
    values = { employee_name: employee_detail.employee_name.to_s, quarter: quarter.to_s, period: period_for(quarter, month),
               reviewer_role: reviewer_role, reviewer_name: reviewer_name.to_s }
    {
      "to_email" => recipient.employee_email.to_s.strip,
      "to_name" => recipient.employee_name.presence || recipient.employee_email.to_s,
      "subject" => Kernel.format(SUBJECTS.fetch(kind.to_s, "KRA MIS notification - %{employee_name}"), values).squish,
      "message" => message.to_s,
      "link" => link_for(kind, reviewer_role),
      "employee_name" => employee_detail.employee_name.to_s,
      "employee_code" => employee_detail.employee_code.to_s,
      "quarter" => quarter.to_s,
      "month" => month.to_s.titleize,
      "reviewer_role" => reviewer_role,
      "reviewer_name" => reviewer_name.to_s,
      "action" => action_for(kind),
      "remarks" => remarks.to_s,
      "mail_type" => kind.to_s
    }
  end

  # krai's page only accepts these action words (anything else is answered
  # "Invalid KRA action." and no mail goes): pending, approved, rejected.
  def self.action_for(kind)
    return "approved" if kind.to_s.end_with?("_approved")
    return "rejected" if kind.to_s.end_with?("_returned")

    "pending"
  end

  # "April (Q1 (APR-JUN))", or just the quarter when the action covers all of it.
  def self.period_for(quarter, month)
    return quarter.presence || "all quarters" if month.blank?

    quarter.present? ? "#{month.to_s.titleize} (#{quarter})" : month.to_s.titleize
  end

  # The review page the recipient opens in the KRA portal.
  def self.link_for(kind, reviewer_role)
    base = (ENV["KRA_MAIL_APP_URL"].presence || DEFAULT_APP_URL).chomp("/")
    observer_number = reviewer_role.to_s[/\AOB([1-4])\z/, 1]
    path = if kind.to_s.start_with?("employee_")
      "/user_details/get_user_detail"
    elsif kind.to_s == "kra_submitted_to_observer" && observer_number
      "/employee_details/observer_#{observer_number}"
    else
      "/employee_details/l1"
    end
    "#{base}#{path}"
  end

  # Full krai address for one kind of mail.
  def self.page_url(kind)
    base = URI.parse(url)
    own_page = kind.present? ? ENV["KRA_MAIL_PAGE_#{kind.to_s.upcase}"].to_s.strip.presence : nil
    return base.to_s if own_page.nil? && base.path.to_s.end_with?(".aspx")

    page = own_page || PAGES.fetch(kind.to_s, DEFAULT_PAGE)
    URI.join(base.to_s.end_with?("/") || base.path.to_s.end_with?(".aspx") ? base.to_s : "#{base}/", page).to_s
  end

  def self.request_uri(kind, params)
    uri = URI.parse(page_url(kind))
    uri.query = URI.encode_www_form(params.slice(*FIELDS))
    uri
  end

  def self.deliver!(kind, params)
    response, final_uri = fetch(request_uri(kind, params))
    where = "[#{final_uri.scheme}://#{final_uri.host}#{final_uri.path}]"
    raise DeliveryError, "Mail service asked for a login #{where}" if login_page?(final_uri)
    raise DeliveryError, "#{failure_message(response)} #{where}" unless success?(response)

    Rails.logger.info("KraMailRelay sent kind=#{kind} to=#{params['to_email']} status=#{response.code} #{where} krai_said=#{reply_text(response).inspect}")
    true
  end

  # krai's page may answer with a redirect (302 "Object moved") to a result
  # page; follow it and judge the page it ends on.
  def self.fetch(uri)
    response = get(uri)
    MAX_REDIRECTS.times do
      break unless response.is_a?(Net::HTTPRedirection) && response["location"].present?

      uri = URI.join(uri.to_s, response["location"])
      response = get(uri)
    end
    [ response, uri ]
  end

  def self.get(uri)
    request = Net::HTTP::Get.new(uri.request_uri)
    request["Accept"] = "application/json"

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                    open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS) do |http|
      http.request(request)
    end
  end

  def self.login_page?(uri)
    uri.path.to_s.downcase.match?(/login|signin|sign_in/)
  end

  # A 2xx answer is a success unless its JSON says otherwise
  # ("success": false, or "status": "error"/"failed").
  def self.success?(response)
    return false unless response.is_a?(Net::HTTPSuccess)

    body = parsed_body(response)
    # krai's page answers 200 with an HTML message, also when it refused to send.
    unless body.is_a?(Hash)
      text = reply_text(response)
      return text.match?(KRAI_SENT) || !text.match?(KRAI_REFUSED)
    end
    return false if body.key?("success") && !ActiveModel::Type::Boolean.new.cast(body["success"])

    !body["status"].to_s.downcase.in?(%w[error failed failure])
  end

  def self.failure_message(response)
    body = parsed_body(response)
    detail = body["message"] || body["error"] if body.is_a?(Hash)
    detail ||= reply_text(response)
    "Mail service returned #{response.code}: #{detail.presence || response.message}"
  end

  # What krai's page said, as plain text, so the log shows whether it really sent.
  def self.reply_text(response)
    response.body.to_s.gsub(%r{<(script|style)[^>]*>.*?</\1>}mi, " ").gsub(/<[^>]+>/, " ").squish.first(200)
  end

  def self.parsed_body(response)
    JSON.parse(response.body.to_s)
  rescue JSON::ParserError
    nil
  end
end

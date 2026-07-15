require "httparty"

class SmsNotificationService
  include HTTParty

  API_URL = "https://sms.yoursmsbox.com/api/sendhttp.php".freeze
  AUTH_KEY = ENV.fetch("SMS_AUTH_KEY", "3230666f72736131353261").freeze
  SENDER = ENV.fetch("SMS_SENDER", "ACTFSA").freeze
  ROUTE = "2".freeze
  COUNTRY = "0".freeze
  DLT_TE_ID = ENV.fetch("SMS_DLT_TE_ID", "1707175983185179621").freeze
  SUBMISSION_TEMPLATE = ENV.fetch(
    "SMS_SUBMISSION_TEMPLATE",
    "Emp-Name: %{employee_name} has submitted his %{quarter} Quarter KRA MIS. Please review and approve in the system. Action For Social Advancement (ASA)"
  ).freeze
  HELP_DESK_SUBMISSION_DLT_TE_ID = "1707178012230155457".freeze
  HELP_DESK_APPROVED_DLT_TE_ID = "1707178012251128478".freeze
  UNICODE = "1".freeze

  class << self
    def send_message(mobile_number, message, dlt_te_id: DLT_TE_ID)
      send_sms(mobile_number, message, dlt_te_id: dlt_te_id)
    end

    def send_sms(mobile_number, message, dlt_te_id: DLT_TE_ID)
      return failure("Mobile number is required") if mobile_number.blank?
      return failure("Message is required") if message.blank?

      clean_mobile = normalize_mobile_number(mobile_number)
      return failure("Invalid mobile number format") unless valid_mobile_number?(clean_mobile)

      Rails.logger.info "Sending SMS to #{clean_mobile}: #{message}"

      response = HTTParty.get(
        API_URL,
        query: {
          authkey: AUTH_KEY,
          mobiles: clean_mobile,
          message: message,
          sender: SENDER,
          route: ROUTE,
          country: COUNTRY,
          DLT_TE_ID: dlt_te_id,
          unicode: UNICODE
        },
        timeout: 30
      )

      Rails.logger.info "SMS API Response: #{response.body}"
      return failure("SMS API HTTP error: #{response.code}") unless response.success?

      parse_response(response.body.to_s)
    rescue => e
      Rails.logger.error "SMS sending failed: #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}"
      failure("SMS sending failed: #{e.message}")
    end

    def submission_message(employee_name, quarter)
      Kernel.format(SUBMISSION_TEMPLATE, employee_name: employee_name, quarter: quarter_template_value(quarter))
    end

    def l1_approval_message(_employee_name, quarter)
      "Your #{quarter} KRA MIS has been approved by L1 Manager. Action For Social Advancement (ASA)"
    end

    def l1_return_message(_employee_name, quarter)
      "Your #{quarter} KRA MIS has been returned by L1 Manager for revision. Please check and resubmit. Action For Social Advancement (ASA)"
    end

    def l2_approval_message(_employee_name, quarter)
      "Your #{quarter} KRA MIS has been approved by L2 Manager. Action For Social Advancement (ASA)"
    end

    def l2_return_message(_employee_name, quarter)
      "Your #{quarter} KRA MIS has been returned by L2 Manager for revision. Please check and resubmit. Action For Social Advancement (ASA)"
    end

    def l3_approval_message(_employee_name, quarter)
      "Your #{quarter} KRA MIS has been finally approved by L3 Manager. Action For Social Advancement (ASA)"
    end

    def l3_return_message(_employee_name, quarter)
      "Your #{quarter} KRA MIS has been returned by L3 Manager for revision. Please check and resubmit. Action For Social Advancement (ASA)"
    end

    def l2_notification_message(employee_name, quarter)
      "#{employee_name}'s #{quarter} KRA MIS has been approved by L1 and is pending your review. Action For Social Advancement (ASA)"
    end

    def l3_notification_message(employee_name, quarter)
      "#{employee_name}'s #{quarter} KRA MIS has been approved by L2 and is pending your review. Action For Social Advancement (ASA)"
    end

    def l1_notification_message_from_l2(employee_name, quarter, action)
      action_text = action == "approved" ? "approved" : "returned"
      "#{employee_name}'s #{quarter} KRA MIS has been #{action_text} by L2 Manager. Action For Social Advancement (ASA)"
    end

    def l1_notification_message_from_l3(employee_name, quarter, action)
      action_text = action == "approved" ? "approved" : "returned"
      "#{employee_name}'s #{quarter} KRA MIS has been #{action_text} by L3 Manager. Action For Social Advancement (ASA)"
    end

    def l2_notification_message_for_l3(employee_name, quarter, action)
      action_text = action == "approved" ? "approved" : "returned"
      "#{employee_name}'s #{quarter} KRA MIS has been #{action_text} by L3 Manager. Action For Social Advancement (ASA)"
    end

    def help_desk_submission_message(recipient_name, ticket_number, request_type, submitter_name)
      "Dear #{recipient_name}, Ticket No. #{ticket_number}: Help Desk #{request_type} has been submitted by #{submitter_name}. Kindly review and take the necessary action. - Action for social advancement (ASA)"
    end

    def help_desk_approved_message(recipient_name, ticket_number, approver_name)
      "Dear #{recipient_name}, Ticket No. #{ticket_number}: Your help desk ticket has been approved by #{approver_name}. Please log in to the system for further details. - Action For Social Advancement (ASA)"
    end

    private

    def normalize_mobile_number(mobile_number)
      mobile_number.to_s.gsub(/[^\d+]/, "").sub(/\A\+/, "")
    end

    def quarter_template_value(quarter)
      case quarter.to_s[/\AQ[1-4]/i]&.upcase
      when "Q1" then "first"
      when "Q2" then "second"
      when "Q3" then "third"
      when "Q4" then "fourth"
      else
        quarter
      end
    end

    def valid_mobile_number?(mobile_number)
      return true if mobile_number.length == 10 && mobile_number.match?(/\A[6-9]\d{9}\z/)

      mobile_number.length == 12 &&
        mobile_number.start_with?("91") &&
        mobile_number[2..].match?(/\A[6-9]\d{9}\z/)
    end

    def parse_response(response_body)
      body = response_body.strip
      parsed = parse_json_response(body)

      return parse_json_result(parsed, body) if parsed.is_a?(Hash)
      return success("SMS sent successfully", response: body) if body.match?(/\A\d+\z/) || body.downcase.include?("success")

      failure("SMS API error: #{body}", response: body)
    end

    def parse_json_response(response_body)
      return nil unless response_body.start_with?("{") && response_body.end_with?("}")

      JSON.parse(response_body)
    rescue JSON::ParserError
      nil
    end

    def parse_json_result(parsed, response_body)
      status = parsed["Status"].to_s
      code = parsed["Code"].to_s
      message_id = parsed["Message-Id"].to_s
      description = parsed["Description"].to_s

      if status.casecmp("Success").zero? && code.present? && code != "0"
        success(
          "SMS sent successfully",
          message_id: message_id.presence,
          provider_status: status,
          provider_code: code,
          provider_description: description.presence,
          response: response_body
        )
      else
        failure(
          "SMS API error: #{description.presence || status.presence || response_body}",
          message_id: message_id.presence,
          provider_status: status.presence,
          provider_code: code.presence,
          provider_description: description.presence,
          response: response_body
        )
      end
    end

    def success(message, details = {})
      { success: true, message: message }.merge(details.compact)
    end

    def failure(message, details = {})
      { success: false, message: message, error: message }.merge(details.compact)
    end
  end
end

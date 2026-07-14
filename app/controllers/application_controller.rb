class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :sign_out_inactive_portal_user
  before_action :configure_permitted_parameters, if: :devise_controller?

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_in, keys: [ :employee_code, :role ])
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :employee_code, :role ])
  end

  # Show the user profile first after every successful login.
  def after_sign_in_path_for(resource)
    settings_path
  end

  def sign_out_inactive_portal_user
    return unless user_signed_in?
    return if devise_controller?
    return if current_user.hod? || current_user.admin?

    employee_detail = portal_employee_detail_for(current_user)
    return unless employee_detail.present? && !employee_detail.portal_active?

    sign_out(current_user)
    redirect_to new_user_session_path, alert: "Your account is inactive. Please contact HOD."
  end

  def portal_employee_detail_for(user)
    user.employee_detail ||
      EmployeeDetail.find_by("lower(employee_email) = ?", user.email.to_s.downcase) ||
      EmployeeDetail.find_by("lower(employee_code) = ?", user.employee_code.to_s.downcase)
  end

  def current_user_identity_code
    current_user&.employee_code.to_s.strip.presence
  end

  def current_user_identity_email
    current_user&.email.to_s.strip.presence
  end

  def has_l1_responsibilities?
    return true if current_user.hod? || current_user.admin?

    code = current_user_identity_code
    email = current_user_identity_email
    return false if code.blank? && email.blank?

    EmployeeDetail.where(
      "(:code != '' AND LOWER(TRIM(COALESCE(l1_code, ''))) = :code) OR (:email != '' AND LOWER(TRIM(COALESCE(l1_employer_name, ''))) = :email)",
      code: code.to_s.downcase,
      email: email.to_s.downcase
    ).exists?
  end

  def has_l2_responsibilities?
    return true if current_user.hod? || current_user.admin?

    code = current_user_identity_code
    email = current_user_identity_email
    return false if code.blank? && email.blank?

    EmployeeDetail.where(
      "(:code != '' AND LOWER(TRIM(COALESCE(l2_code, ''))) = :code) OR (:email != '' AND LOWER(TRIM(COALESCE(l2_employer_name, ''))) = :email)",
      code: code.to_s.downcase,
      email: email.to_s.downcase
    ).exists?
  end

  def has_quarterly_pli_responsibilities?
    has_l1_responsibilities?
  end

  def normalize_financial_year(value)
    year = value.to_s.strip
    return nil if year.blank?

    match = year.match(/\A(\d{4})\s*-\s*(\d{2}|\d{4})\z/)
    return year unless match

    start_year = match[1].to_i
    end_year = match[2].length == 2 ? ((start_year / 100) * 100) + match[2].to_i : match[2].to_i
    end_year += 100 if end_year <= start_year

    "#{start_year}-#{end_year}"
  end

  def current_financial_year
    start_year = Date.current.month >= 4 ? Date.current.year : Date.current.year - 1
    "#{start_year}-#{start_year + 1}"
  end

  def l1_pending_reviews_count
    return 0 unless user_signed_in? && has_l1_responsibilities?

    employees = if current_user.hod? || current_user.admin?
      EmployeeDetail.includes(user_details: [ :activity, achievements: :achievement_remark ]).to_a
    else
      code = current_user_identity_code
      email = current_user_identity_email
      return 0 if code.blank? && email.blank?

      EmployeeDetail.where(
        "(:code != '' AND LOWER(TRIM(COALESCE(l1_code, ''))) = :code) OR (:email != '' AND LOWER(TRIM(COALESCE(l1_employer_name, ''))) = :email)",
        code: code.to_s.downcase,
        email: email.to_s.downcase
      ).includes(user_details: [ :activity, achievements: :achievement_remark ]).to_a
    end

    employees.sum do |employee_detail|
      l1_pending_months_for_employee(employee_detail, current_financial_year)
    end
  rescue StandardError
    0
  end

  def l1_pending_reviews?
    l1_pending_reviews_count.positive?
  end

  def l1_actionable_achievement?(achievement)
    employee_detail = achievement.user_detail&.employee_detail
    return false if employee_detail.blank?

    observer_chain_approved_for_achievement?(employee_detail, achievement.user_detail&.financial_year, achievement.month)
  end

  def l1_pending_months_for_employee(employee_detail, financial_year)
    details = employee_detail.user_details.select do |detail|
      detail.financial_year.to_s == financial_year.to_s && detail.activity.present?
    end
    return 0 if details.empty?

    review_months_for_sidebar.count do |month|
      achievements = details.flat_map do |detail|
        next [] unless sidebar_target_present_for_detail_month?(detail, month)

        detail.achievements.select do |achievement|
          achievement.month.to_s.downcase == month && achievement.achievement.present?
        end
      end
      next false if achievements.empty?
      next false unless observer_chain_approved_for_achievement?(employee_detail, financial_year, month)

      sidebar_l1_month_status(achievements) == "pending"
    end
  end

  def review_months_for_sidebar
    %w[april may june july august september october november december january february march]
  end

  def sidebar_target_present_for_detail_month?(detail, month)
    return false unless detail.respond_to?(month)

    target_value = detail.public_send(month).to_s.strip
    return false if target_value.blank?

    target_text = target_value.delete(",")
    target_is_numeric = target_text.match?(/\A-?\d+(?:\.\d+)?\z/)
    !target_is_numeric || target_text.to_f.positive?
  end

  def sidebar_l1_month_status(achievements)
    statuses = achievements.map { |achievement| achievement.status.presence || "pending" }
    has_l1_approval = achievements.any? do |achievement|
      achievement.achievement_remark&.l1_percentage.present? ||
        achievement.achievement_remark&.l1_remarks.present?
    end
    has_l2_approval = achievements.any? do |achievement|
      achievement.achievement_remark&.l2_percentage.present? ||
        achievement.achievement_remark&.l2_remarks.present?
    end

    return "l2_returned" if statuses.any? { |status| status == "l2_returned" }
    return "l2_approved" if statuses.all? { |status| status == "l2_approved" } || has_l2_approval
    return "l1_returned" if statuses.any? { |status| status == "l1_returned" }
    return "l1_approved" if statuses.all? { |status| status == "l1_approved" } || has_l1_approval

    "pending"
  end

  def observer_chain_approved_for_achievement?(employee_detail, financial_year, month)
    assigned_levels = %w[obs_code1 obs_code2 obs_code3 obs_code4].select do |observer_level|
      employee_detail.public_send(observer_level).to_s.strip.present?
    end
    return true if assigned_levels.empty?

    quarter = quarter_name_for_sidebar_month(month)
    return false if quarter.blank? || financial_year.blank?

    assigned_levels.all? do |observer_level|
      ObserverPliReview.exists?(
        employee_detail: employee_detail,
        financial_year: financial_year,
        quarter: quarter,
        month: month.to_s.downcase,
        observer_level: observer_level,
        status: "approved"
      )
    end
  end

  def quarter_name_for_sidebar_month(month)
    {
      "april" => "Q1", "may" => "Q1", "june" => "Q1",
      "july" => "Q2", "august" => "Q2", "september" => "Q2",
      "october" => "Q3", "november" => "Q3", "december" => "Q3",
      "january" => "Q4", "february" => "Q4", "march" => "Q4"
    }[month.to_s.downcase]
  end

  helper_method :has_l1_responsibilities?, :has_l2_responsibilities?, :has_quarterly_pli_responsibilities?,
                :l1_pending_reviews_count, :l1_pending_reviews?
end

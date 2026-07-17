class Users::SessionsController < Devise::SessionsController
  skip_before_action :verify_authenticity_token, only: [ :create ] # only for testing, enable CSRF later

  def create
    submitted_code = params[:user][:employee_code].to_s.strip
    submitted_password = params[:user][:password]

    if submitted_code.blank?
      flash[:alert] = "Employee code is required."
      redirect_to new_session_path(resource_name) and return
    end

    employee_detail = find_employee_detail(submitted_code)

    user = User.find_by("lower(employee_code) = ?", submitted_code.downcase)
    user ||= provision_employee_account(employee_detail)

    if user.nil? && employee_detail.present? && !employee_detail.portal_active?
      flash[:alert] = "Your account is inactive. Please contact HOD."
      redirect_to new_session_path(resource_name) and return
    end

    if user.nil?
      flash[:alert] = "No account found with that employee code."
      redirect_to new_session_path(resource_name) and return
    end

    unless valid_password_for?(user, submitted_password) || restore_default_portal_password?(user, employee_detail, submitted_password)
      flash[:alert] = "Incorrect password."
      redirect_to new_session_path(resource_name) and return
    end

    employee_detail ||= find_employee_detail_for_user(user)
    if employee_detail.present? && !employee_detail.portal_active?
      flash[:alert] = "Your account is inactive. Please contact HOD."
      redirect_to new_session_path(resource_name) and return
    end

    sign_in(resource_name, user)
    redirect_to after_sign_in_path_for(user)
  end

  private

  def provision_employee_account(employee)
    return unless employee
    return unless employee.portal_active?

    employee.ensure_portal_user!
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("Portal login auto-provision failed for #{employee.employee_email}: #{e.message}")
    nil
  end

  def find_employee_detail(submitted_code)
    return if submitted_code.blank?

    EmployeeDetail.find_by("lower(employee_code) = ?", submitted_code.downcase)
  end

  def find_employee_detail_for_user(user)
    return unless user

    user.employee_detail ||
      EmployeeDetail.find_by("lower(employee_email) = ?", user.email.to_s.downcase) ||
      EmployeeDetail.find_by("lower(employee_code) = ?", user.employee_code.to_s.downcase)
  end

  def valid_password_for?(user, password)
    user.valid_password?(password)
  rescue BCrypt::Errors::InvalidHash
    false
  end

  def restore_default_portal_password?(user, employee_detail, submitted_password)
    return false unless submitted_password == EmployeeDetail::DEFAULT_PORTAL_PASSWORD
    return false unless employee_detail&.portal_active?
    return false if user.password_changed_at.present?

    user.skip_password_changed_tracking = true
    user.password = EmployeeDetail::DEFAULT_PORTAL_PASSWORD
    user.password_confirmation = EmployeeDetail::DEFAULT_PORTAL_PASSWORD
    user.save!
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("Portal default password restore failed for #{user.employee_code}: #{e.message}")
    false
  end
end

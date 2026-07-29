class SettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user

  def show
  end

  def update
    if @user.update(user_params)
      if request.xhr?
        render json: {
          success: true,
          message: "Profile updated successfully!",
          avatar_url: @user.profile_image.attached? ? url_for(@user.profile_image) : nil
        }
      else
        flash[:notice] = "Profile updated successfully!"
        redirect_to settings_path
      end
    else
      if request.xhr?
        render json: {
          success: false,
          errors: @user.errors.full_messages
        }
      else
        flash[:alert] = "Failed to update profile: #{@user.errors.full_messages.join(', ')}"
        render :show
      end
    end
  end

  def update_password
    if @user.update_with_password(password_params)
      bypass_sign_in(@user)
      flash[:notice] = "Password updated successfully!"
      redirect_to settings_path
    else
      flash[:alert] = "Failed to update password: #{@user.errors.full_messages.join(', ')}"
      render :show
    end
  end

  private

  def set_user
    @user = current_user
    @employee_detail = portal_employee_detail_for(@user)
    sync_login_identity_from_employee!
    @profile_name = @employee_detail&.employee_name.to_s.strip.presence || @user.email.to_s.split("@").first.to_s.titleize
    @profile_email = @employee_detail&.employee_email.to_s.strip.presence || @user.email
    @reviewer_assignments = profile_reviewer_assignments(@employee_detail)
  end

  def sync_login_identity_from_employee!
    return if @employee_detail.blank?

    canonical_email = @employee_detail.employee_email.to_s.strip.downcase.presence
    canonical_code = @employee_detail.employee_code.to_s.strip.presence
    return if canonical_email.blank? || canonical_code.blank?
    return if @user.email.to_s.strip.downcase == canonical_email && @user.employee_code.to_s.strip == canonical_code

    @user.update!(email: canonical_email, employee_code: canonical_code)
    @employee_detail.update_column(:user_id, @user.id) if @employee_detail.user_id != @user.id
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("Profile login identity sync failed for EmployeeDetail##{@employee_detail.id}: #{e.message}")
  end

  def user_params
    params.require(:user).permit(:email, :employee_code, :profile_image)
  end

  def password_params
    params.require(:user).permit(:current_password, :password, :password_confirmation)
  end

  def profile_reviewer_assignments(employee)
    return [] if employee.blank?

    assignments = []
    l1 = reviewer_details(employee.l1_code, fallback_name: employee.l1_employer_name)
    assignments << l1.merge(label: "L1 Manager") if l1

    EmployeeDetail::OBSERVER_CODE_FIELDS.each_with_index do |field, index|
      reviewer = reviewer_details(employee.public_send(field))
      assignments << reviewer.merge(label: "Observer #{index + 1}") if reviewer
    end
    assignments
  end

  def reviewer_details(raw_code, fallback_name: nil)
    code = raw_code.to_s.strip
    return nil unless EmployeeDetail.assigned_code?(code)

    normalized_code = code.split(/\s+-\s+/, 2).first.to_s.strip
    reviewer = EmployeeDetail.where("LOWER(TRIM(employee_code)) = ?", normalized_code.downcase).first ||
               EmployeeDetail.where("LOWER(employee_code) LIKE ?", "#{normalized_code.downcase}%").first
    name = reviewer&.employee_name.to_s.strip.presence || fallback_name.to_s.strip.presence
    display_code = reviewer&.employee_code.to_s.strip.presence || normalized_code.presence
    return nil if name.blank? || display_code.blank?

    { name: name, code: display_code }
  end
end

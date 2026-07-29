class EmployeeSidebarAccessesController < ApplicationController
  before_action :require_access_manager!

  def index
    @query = params[:q].to_s.strip
    @employees = employee_scope
    @accesses = EmployeeSidebarAccess.where(employee_detail_id: @employees.select(:id)).index_by(&:employee_detail_id)
  end

  def bulk_update
    if params[:direct_toggle].present?
      toggle_single_access!
      return
    end

    menu_keys = Array(params[:menu_keys]) & EmployeeSidebarAccess::MENU_ATTRIBUTES.keys
    employees = selected_employees

    if menu_keys.empty? || employees.none?
      redirect_to employee_sidebar_accesses_path(q: params[:q]), alert: "Please select at least one employee and one menu."
      return
    end

    active = ActiveModel::Type::Boolean.new.cast(params[:active])
    EmployeeSidebarAccess.transaction do
      employees.find_each do |employee|
        access = EmployeeSidebarAccess.find_or_initialize_by(employee_detail: employee)
        menu_keys.each { |key| access.public_send("#{EmployeeSidebarAccess::MENU_ATTRIBUTES.fetch(key)}=", active) }
        access.save!
      end
    end

    redirect_to employee_sidebar_accesses_path(q: params[:q]),
                notice: "#{employees.count} employee(s) ke selected menus #{active ? 'Active' : 'Inactive'} kar diye gaye."
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("Employee sidebar access update failed: #{e.message}")
    redirect_to employee_sidebar_accesses_path(q: params[:q]), alert: "Sidebar access update failed."
  end

  private

  def toggle_single_access!
    employee_id, menu_key = params[:direct_toggle].to_s.split(":", 2)
    attribute = EmployeeSidebarAccess::MENU_ATTRIBUTES[menu_key]
    employee = EmployeeDetail.find_by(id: employee_id)

    if employee.blank? || attribute.blank?
      redirect_to employee_sidebar_accesses_path(q: params[:q]), alert: "Invalid employee or menu."
      return
    end

    access = EmployeeSidebarAccess.find_or_initialize_by(employee_detail: employee)
    current_status = access.new_record? ? menu_key != "archived" : access.public_send(attribute)
    access.public_send("#{attribute}=", !current_status)
    access.save!

    redirect_to employee_sidebar_accesses_path(q: params[:q]),
                notice: "#{employee.employee_code} ka #{menu_key.humanize} #{access.public_send(attribute) ? 'Active' : 'Inactive'} kar diya gaya."
  end

  def require_access_manager!
    return if current_user&.hod? || current_user&.admin?

    redirect_to root_path, alert: "You are not authorized to manage sidebar access."
  end

  def employee_scope
    scope = EmployeeDetail.where.not(employee_code: [ nil, "" ]).order(:employee_code)
    return scope if @query.blank?

    term = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
    scope.where("employee_code ILIKE :term OR employee_name ILIKE :term", term: term)
  end

  def selected_employees
    return employee_scope_for_bulk if ActiveModel::Type::Boolean.new.cast(params[:select_all])

    EmployeeDetail.where(id: Array(params[:employee_ids]).filter_map { |id| Integer(id, exception: false) })
  end

  def employee_scope_for_bulk
    @query = params[:q].to_s.strip
    employee_scope
  end
end

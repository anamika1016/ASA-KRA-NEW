class EmployeeSidebarAccess < ApplicationRecord
  MENU_ATTRIBUTES = {
    "achievement_form" => "achievement_form_active",
    "submitted_targets" => "submitted_targets_active",
    "observer_1" => "observer_1_active",
    "observer_2" => "observer_2_active",
    "observer_3" => "observer_3_active",
    "observer_4" => "observer_4_active",
    "l1" => "l1_active",
    "quarterly_pli" => "quarterly_pli_active",
    "quarterly_pli_report" => "quarterly_pli_report_active",
    "archived" => "archived_active"
  }.freeze

  belongs_to :employee_detail

  validates :employee_detail_id, uniqueness: true

  after_save { Current.employee_sidebar_accesses = nil }
  after_destroy { Current.employee_sidebar_accesses = nil }

  def self.enabled_for?(employee_detail, menu_key)
    return true if employee_detail.blank?

    attribute = MENU_ATTRIBUTES[menu_key.to_s]
    return false if attribute.blank?

    access = cached_for(employee_detail.id)
    return false if menu_key.to_s == "archived" && access.blank?

    access&.public_send(attribute) != false
  rescue ActiveRecord::StatementInvalid
    true
  end

  # The sidebar checks several menu keys for the same employee on every render,
  # so remember the row for the duration of the request.
  def self.cached_for(employee_detail_id)
    cache = (Current.employee_sidebar_accesses ||= {})
    return cache[employee_detail_id] if cache.key?(employee_detail_id)

    cache[employee_detail_id] = find_by(employee_detail_id: employee_detail_id)
  end
end

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
    "archived" => "archived_active"
  }.freeze

  belongs_to :employee_detail

  validates :employee_detail_id, uniqueness: true

  def self.enabled_for?(employee_detail, menu_key)
    return true if employee_detail.blank?

    attribute = MENU_ATTRIBUTES[menu_key.to_s]
    return false if attribute.blank?

    access = find_by(employee_detail_id: employee_detail.id)
    return false if menu_key.to_s == "archived" && access.blank?

    access&.public_send(attribute) != false
  rescue ActiveRecord::StatementInvalid
    true
  end
end

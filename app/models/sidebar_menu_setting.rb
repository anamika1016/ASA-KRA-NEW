class SidebarMenuSetting < ApplicationRecord
  MENU_KEYS = %w[observer_1 observer_2 observer_3 observer_4 l1 quarterly_pli].freeze

  validates :menu_key, presence: true, inclusion: { in: MENU_KEYS }, uniqueness: true

  def self.active_for?(menu_key)
    return false unless MENU_KEYS.include?(menu_key.to_s)

    find_by(menu_key: menu_key.to_s)&.active != false
  rescue ActiveRecord::StatementInvalid
    true
  end

  def self.toggle!(menu_key)
    setting = find_or_create_by!(menu_key: menu_key.to_s) { |row| row.active = true }
    setting.update!(active: !setting.active?)
    setting
  end
end

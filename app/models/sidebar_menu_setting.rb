class SidebarMenuSetting < ApplicationRecord
  MENU_KEYS = %w[observer_1 observer_2 observer_3 observer_4 l1 quarterly_pli quarterly_pli_report].freeze

  validates :menu_key, presence: true, inclusion: { in: MENU_KEYS }, uniqueness: true

  def self.active_for?(menu_key)
    return false unless MENU_KEYS.include?(menu_key.to_s)

    settings_by_key[menu_key.to_s]&.active != false
  rescue ActiveRecord::StatementInvalid
    true
  end

  # The sidebar asks about every menu key on each render. Load the whole table
  # once per request instead of issuing a find_by per question.
  def self.settings_by_key
    Current.sidebar_menu_settings ||= all.index_by { |setting| setting.menu_key.to_s }
  end

  def self.toggle!(menu_key)
    setting = find_or_create_by!(menu_key: menu_key.to_s) { |row| row.active = true }
    setting.update!(active: !setting.active?)
    Current.sidebar_menu_settings = nil
    setting
  end
end

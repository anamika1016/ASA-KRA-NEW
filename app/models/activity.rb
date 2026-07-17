require "cgi"

class Activity < ApplicationRecord
  SPREADSHEET_MARKUP_PATTERN = /<\/?[a-z][^>]*>/i.freeze

  belongs_to :department

  alias_attribute :key_result_indicator, :activity_name
  alias_attribute :annual_target_fy, :annual_target_fy_2026_27

  has_many :user_details

  before_validation :clean_activity_name_markup

  def self.clean_spreadsheet_markup(value)
    return nil if value.nil?

    text = value.to_s.strip
    return text if text.blank?

    if text.match?(SPREADSHEET_MARKUP_PATTERN)
      text = Rails::Html::FullSanitizer.new.sanitize(text).to_s
    end

    CGI.unescapeHTML(text.gsub(/\*\*(.*?)\*\*/m, "\\1")).squish
  end

  private

  def clean_activity_name_markup
    self.activity_name = self.class.clean_spreadsheet_markup(activity_name)
  end
end

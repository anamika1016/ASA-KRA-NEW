class CleanHtmlMarkupFromActivityNames < ActiveRecord::Migration[8.0]
  class ActivityRecord < ActiveRecord::Base
    self.table_name = "activities"
  end

  SPREADSHEET_MARKUP_PATTERN = /<\/?[a-z][^>]*>/i.freeze

  def up
    sanitizer = Rails::Html::FullSanitizer.new

    ActivityRecord.where("activity_name LIKE ?", "%<%").find_each do |activity|
      cleaned_name = clean_spreadsheet_markup(activity.activity_name, sanitizer)
      next if cleaned_name.blank? || cleaned_name == activity.activity_name

      activity.update_columns(activity_name: cleaned_name, updated_at: Time.current)
    end
  end

  def down
    # Irreversible: stripped spreadsheet/HTML markup cannot be reconstructed.
  end

  private

  def clean_spreadsheet_markup(value, sanitizer)
    text = value.to_s.strip
    return text if text.blank?

    text = sanitizer.sanitize(text).to_s if text.match?(SPREADSHEET_MARKUP_PATTERN)
    text.gsub(/\*\*(.*?)\*\*/m, "\\1").squish
  end
end

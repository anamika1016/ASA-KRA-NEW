class UserDetail < ApplicationRecord
  MANUAL_KRI_THEME = "manual_kri"
  MONTH_KEYS = %w[april may june july august september october november december january february march].freeze

  belongs_to :department
  belongs_to :activity
  belongs_to :employee_detail, optional: true  # optional if it can be nil
  has_many :target_submissions, dependent: :destroy
  has_many :achievements, dependent: :destroy

  # Manual KRIs created by an accidental retry can point at separate Activity
  # rows while representing the same employee/year/month/name. Keep one
  # canonical row in review and entry screens without collapsing normal KRIs.
  def self.deduplicate_manual_kri_rows(records)
    seen = {}

    Array(records).select do |detail|
      activity = detail.activity
      next true unless activity&.theme_name.to_s == MANUAL_KRI_THEME

      month = MONTH_KEYS.find do |month_key|
        value = detail.public_send(month_key).to_s.delete(",").strip
        value.present? && (!value.match?(/\A-?\d+(?:\.\d+)?\z/) || value.to_f.positive?)
      end
      normalized_name = activity.activity_name.to_s.squish.downcase
      key = [ detail.employee_detail_id, detail.financial_year.to_s, month, normalized_name ]
      duplicate = seen.key?(key)
      seen[key] = detail.id unless duplicate
      !duplicate
    end
  end
end

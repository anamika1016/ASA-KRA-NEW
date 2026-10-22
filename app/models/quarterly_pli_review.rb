class QuarterlyPliReview < ApplicationRecord
  belongs_to :employee_detail
  belongs_to :reviewed_by, class_name: "User", optional: true

  validates :financial_year, :quarter, presence: true
  validates :quarter, inclusion: { in: %w[Q1 Q2 Q3 Q4] }
  validates :status, inclusion: { in: %w[approved returned] }
  validates :final_percentage,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 },
            allow_nil: true

  after_save { Current.quarterly_pli_reviews = nil }
  after_destroy { Current.quarterly_pli_reviews = nil }

  # Listing screens look a review up per rendered row. An employee has at most
  # four per year, so keep them in a request-scoped cache instead.
  def self.cached_for(employee_detail_id, financial_year)
    cache = (Current.quarterly_pli_reviews ||= {})
    cache[[ employee_detail_id, financial_year ]] ||=
      where(employee_detail_id: employee_detail_id, financial_year: financial_year)
        .includes(:reviewed_by).to_a
  end

  def self.prime_cache(employee_detail_ids, financial_year)
    cache = (Current.quarterly_pli_reviews ||= {})
    missing = Array(employee_detail_ids).compact.uniq.reject { |id| cache.key?([ id, financial_year ]) }
    return if missing.empty?

    grouped = where(employee_detail_id: missing, financial_year: financial_year)
                .includes(:reviewed_by).group_by(&:employee_detail_id)
    missing.each { |id| cache[[ id, financial_year ]] = grouped[id] || [] }
  end

  def self.cached_find(employee_detail_id, financial_year, quarter)
    cached_for(employee_detail_id, financial_year).find do |review|
      ObserverPliReview.column_matches?(review.quarter, quarter)
    end
  end
end

class ObserverPliReview < ApplicationRecord
  belongs_to :employee_detail
  belongs_to :reviewed_by, class_name: "User", optional: true

  validates :financial_year, :quarter, :observer_level, presence: true
  validates :quarter, inclusion: { in: %w[Q1 Q2 Q3 Q4] }
  validates :month, inclusion: { in: %w[april may june july august september october november december january february march] }, allow_blank: true
  validates :observer_level, inclusion: { in: ApplicationHelper::OBSERVER_LEVELS }
  validates :status, inclusion: { in: %w[pending approved returned] }

  after_save { Current.observer_pli_reviews = nil }
  after_destroy { Current.observer_pli_reviews = nil }

  # Review pages ask "is this employee/month/level approved?" once per rendered
  # row, which used to be one query each. Rows for an employee are few, so keep
  # them in a request-scoped cache and let callers prime it in bulk.
  def self.cached_for(employee_detail_id, financial_year)
    cache = (Current.observer_pli_reviews ||= {})
    cache[[ employee_detail_id, financial_year ]] ||=
      where(employee_detail_id: employee_detail_id, financial_year: financial_year).to_a
  end

  def self.prime_cache(employee_detail_ids, financial_year)
    cache = (Current.observer_pli_reviews ||= {})
    missing = Array(employee_detail_ids).compact.uniq.reject { |id| cache.key?([ id, financial_year ]) }
    return if missing.empty?

    grouped = where(employee_detail_id: missing, financial_year: financial_year).group_by(&:employee_detail_id)
    missing.each { |id| cache[[ id, financial_year ]] = grouped[id] || [] }
  end

  # Mirrors SQL equality: a NULL column never matches a value, and only a nil
  # search term matches NULL. Keeps the cached lookups identical to the
  # find_by/exists? calls they replaced, including for rows with a NULL month.
  def self.column_matches?(column_value, search_value)
    return column_value.nil? if search_value.nil?

    !column_value.nil? && column_value == search_value
  end

  def self.cached_matches(employee_detail_id, financial_year, quarter, month, observer_level)
    cached_for(employee_detail_id, financial_year).select do |review|
      column_matches?(review.quarter, quarter) &&
        column_matches?(review.month, month) &&
        column_matches?(review.observer_level, observer_level)
    end
  end

  def self.cached_find(employee_detail_id, financial_year, quarter, month, observer_level)
    cached_matches(employee_detail_id, financial_year, quarter, month, observer_level).first
  end

  def self.cached_approved?(employee_detail_id, financial_year, quarter, month, observer_level)
    cached_matches(employee_detail_id, financial_year, quarter, month, observer_level)
      .any? { |review| review.status == "approved" }
  end
end

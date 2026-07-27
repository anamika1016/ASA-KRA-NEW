require "test_helper"

class UserDetailTest < ActiveSupport::TestCase
  test "deduplicates identical manual KRI retries for the same employee year and month" do
    activity = Activity.new(activity_name: "ILO Audit preparation", theme_name: "manual_kri")
    first = UserDetail.new(id: 101, employee_detail_id: 25, financial_year: "2026-2027", may: "1", activity: activity)
    retry_row = UserDetail.new(id: 102, employee_detail_id: 25, financial_year: "2026-2027", may: "1", activity: activity)

    assert_equal [ first ], UserDetail.deduplicate_manual_kri_rows([ first, retry_row ])
  end

  test "keeps the same manual KRI name when it belongs to different months" do
    activity = Activity.new(activity_name: "ILO Audit preparation", theme_name: "manual_kri")
    april_row = UserDetail.new(id: 101, employee_detail_id: 25, financial_year: "2026-2027", april: "1", activity: activity)
    may_row = UserDetail.new(id: 102, employee_detail_id: 25, financial_year: "2026-2027", may: "1", activity: activity)

    assert_equal [ april_row, may_row ], UserDetail.deduplicate_manual_kri_rows([ april_row, may_row ])
  end
end

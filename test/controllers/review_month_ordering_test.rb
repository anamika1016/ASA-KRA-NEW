require "test_helper"

# Review listings are ordered by the month's position in the financial year.
# Sorting on the month name instead put august before july, so these tests pin
# the ordering down for each screen that lists months.
class ReviewMonthOrderingTest < ActiveSupport::TestCase
  setup do
    Current.reset
    @controller = EmployeeDetailsController.new
    @department = Department.create!(department_type: "Ordering")
    @activity = Activity.create!(
      department: @department, activity_name: "Visits", unit: "Count", weight: 1
    )
  end

  teardown { Current.reset }

  test "month sort index follows the financial year, not the alphabet" do
    order = %w[april may june july august september october november december january february march]
    indexes = order.map { |month| @controller.send(:review_month_sort_index, month) }

    assert_equal (0..11).to_a, indexes
    assert_equal indexes.sort, indexes
  end

  test "month sort index is case and whitespace tolerant and survives junk" do
    assert_equal 3, @controller.send(:review_month_sort_index, " July ")
    assert_equal 3, @controller.send(:review_month_sort_index, "JULY")
    assert_equal 12, @controller.send(:review_month_sort_index, "not-a-month")
    assert_equal 12, @controller.send(:review_month_sort_index, nil)
  end

  test "L1 listing puts the latest month first and groups employees under it" do
    zara = employee_with_months("Zara Khan", "ORD001", %w[april july september])
    amit = employee_with_months("Amit Rao", "ORD002", %w[july september])

    rows = @controller.send(
      :build_monthly_employee_data,
      [ zara, amit ],
      approval_level: "l1",
      financial_year: "2026-2027"
    ).values

    assert_equal [
      [ "september", "Amit Rao" ],
      [ "september", "Zara Khan" ],
      [ "july", "Amit Rao" ],
      [ "july", "Zara Khan" ],
      [ "april", "Zara Khan" ]
    ], rows.map { |row| [ row[:month], row[:employee].employee_name ] }
  end

  test "activities inside a quarter read chronologically" do
    employee = employee_with_months("Quarter Case", "ORD003", %w[july august september])

    activities = @controller.send(
      :get_all_activities_for_quarter,
      employee.user_details.to_a,
      "Q2"
    )

    assert_equal %w[july august september], activities.map { |activity| activity[:month] }
  end

  test "observer listing shows submitted months first, latest of them on top" do
    # Targets exist for the whole quarter but only two months were submitted,
    # so the untouched month must sink below the ones with data.
    employee = EmployeeDetail.create!(
      employee_name: "Observer Case", employee_code: "ORD004",
      department: "Ordering", obs_code1: "OBSX"
    )
    user_detail = UserDetail.create!(
      department: @department, activity: @activity, employee_detail: employee,
      financial_year: "2026-2027", july: "100", august: "100", september: "100"
    )
    %w[july september].each do |month|
      Achievement.create!(user_detail: user_detail, month: month, achievement: "90")
    end
    employee.reload

    rows = @controller.send(
      :build_observer_pli_rows,
      [ employee ],
      observer_level: "obs_code1",
      financial_year: "2026-2027",
      quarter: "Q2"
    )

    assert_equal %w[september july august], rows.map { |row| row[:month] }
    assert_equal [ true, true, false ], rows.map { |row| row[:submitted] }
  end

  private

  def employee_with_months(name, code, months)
    employee = EmployeeDetail.create!(
      employee_name: name, employee_code: code, department: "Ordering"
    )
    attributes = months.to_h { |month| [ month.to_sym, "100" ] }
    user_detail = UserDetail.create!(
      { department: @department, activity: @activity, employee_detail: employee,
        financial_year: "2026-2027" }.merge(attributes)
    )
    months.each do |month|
      Achievement.create!(user_detail: user_detail, month: month, achievement: "90")
    end
    employee.reload
  end
end

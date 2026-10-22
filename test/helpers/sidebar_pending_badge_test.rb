require "test_helper"

# observer_pending_reviews? no longer counts every pending review; it asks the
# database whether one exists. observer_pending_reviews_count still holds the
# original logic, so it is the reference: the two must always agree.
class SidebarPendingBadgeTest < ActionView::TestCase
  include ApplicationHelper

  MONTHS = %w[april may june july august september october november december january february march].freeze

  attr_reader :current_user

  setup do
    Current.reset
    @financial_year = sidebar_current_financial_year
    @current_user = User.create!(
      email: "badge-admin@example.com", password: "Password1!",
      role: "hod", employee_code: "BADGEADMIN"
    )
    @department = Department.create!(department_type: "Badge")
    @activity = Activity.create!(
      department: @department, activity_name: "Badge Activity", unit: "Count", weight: 1
    )
  end

  teardown { Current.reset }

  # current_user is a controller method; the helper under test only needs it to
  # resolve the signed-in reviewer.
  def menu_access_enabled?(_menu_key, _user = nil) = true

  test "agrees with the count when nothing is submitted" do
    employee_with(months: [])
    assert_badges_agree
  end

  test "agrees with the count when a month is submitted and unreviewed" do
    employee_with(months: %w[july])
    assert_badges_agree
  end

  test "agrees with the count when every submitted month is approved" do
    employee = employee_with(months: %w[july august])
    approve(employee, "july")
    approve(employee, "august")
    assert_badges_agree
  end

  test "agrees with the count when only some months are approved" do
    employee = employee_with(months: %w[july august september])
    approve(employee, "july")
    assert_badges_agree
  end

  test "a non-approved review still counts as pending" do
    employee = employee_with(months: %w[july])
    approve(employee, "july", status: "pending")
    assert_badges_agree
  end

  test "an approval for a different observer level does not clear the dot" do
    employee = employee_with(months: %w[july])
    approve(employee, "july", observer_level: "obs_code2")
    assert_badges_agree
  end

  test "an approval in another financial year does not clear the dot" do
    employee = employee_with(months: %w[july])
    approve(employee, "july", financial_year: "2099-2100")
    assert_badges_agree
  end

  test "blank achievements are ignored" do
    employee = employee_with(months: %w[july])
    employee.user_details.flat_map(&:achievements).each { |a| a.update!(achievement: "   ") }
    Current.reset
    assert_badges_agree
  end

  test "an unrecognised month is ignored" do
    employee = employee_with(months: %w[july])
    employee.user_details.flat_map(&:achievements).each { |a| a.update_column(:month, "smarch") }
    Current.reset
    assert_badges_agree
  end

  test "a mixed-case stored month behaves the same in both paths" do
    employee = employee_with(months: %w[july])
    employee.user_details.flat_map(&:achievements).each { |a| a.update_column(:month, "July") }
    Current.reset
    assert_badges_agree
  end

  test "an unassigned observer code placeholder is not treated as assigned" do
    employee_with(months: %w[july], obs_code: "N/A")
    assert_badges_agree
  end

  test "all four observer levels agree across a mixed dataset" do
    first = employee_with(months: %w[april july], code: "BADGE001")
    employee_with(months: %w[august], code: "BADGE002")
    third = employee_with(months: %w[september december], code: "BADGE003")
    approve(first, "april")
    approve(third, "september", observer_level: "obs_code3")
    assert_badges_agree
  end

  private

  def assert_badges_agree
    Current.reset
    OBSERVER_LEVELS.each do |level|
      Current.reset
      expected = observer_pending_reviews_count(level).positive?
      Current.reset
      actual = observer_pending_reviews?(level)

      assert_equal expected, actual, "#{level}: SQL badge disagrees with the counted badge"
    end
  end

  def employee_with(months:, code: "BADGE000", obs_code: "BADGEADMIN")
    employee = EmployeeDetail.create!(
      employee_name: "Badge #{code}", employee_code: code, department: "Badge",
      obs_code1: obs_code, obs_code2: obs_code, obs_code3: obs_code, obs_code4: obs_code
    )
    detail = UserDetail.create!(
      department: @department, activity: @activity, employee_detail: employee,
      financial_year: @financial_year, **MONTHS.to_h { |m| [ m.to_sym, "100" ] }
    )
    months.each { |month| Achievement.create!(user_detail: detail, month: month, achievement: "90") }
    employee.reload
  end

  def approve(employee, month, observer_level: "obs_code1", status: "approved", financial_year: nil)
    ObserverPliReview.create!(
      employee_detail: employee,
      financial_year: financial_year || @financial_year,
      quarter: quarter_name_for_month(month),
      month: month,
      observer_level: observer_level,
      status: status
    )
  end
end

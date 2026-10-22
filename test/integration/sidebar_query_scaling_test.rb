require "test_helper"

# The sidebar renders on every page and its "pending review" badges used to ask
# the database once per employee, per month, per observer level. On production
# that turned an otherwise trivial page into thousands of queries.
#
# These tests pin the important property: the sidebar's query count must not
# grow with the number of employees. Absolute numbers would be brittle, so each
# test compares a small dataset against a much larger one.
class SidebarQueryScalingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  MONTHS = %w[april may june july august september].freeze

  setup do
    Current.reset
    @admin = User.create!(
      email: "scale-admin@example.com", password: "Password1!",
      role: "hod", employee_code: "SCALEADMIN"
    )
    @department = Department.create!(department_type: "Scale", financial_year: "2026-2027")
    @activities = 3.times.map do |i|
      Activity.create!(department: @department, activity_name: "Scale Activity #{i}",
                       unit: "Count", weight: 1, annual_target_fy_2026_27: "1200")
    end
  end

  teardown { Current.reset }

  test "sidebar query count does not grow with the number of employees" do
    seed_employees(3)
    sign_in @admin, scope: :user
    get "/settings"
    assert_response :success
    small = measure("/settings")

    seed_employees(27, offset: 3)
    large = measure("/settings")

    assert_response :success
    assert_operator large, :<=, small + 2,
      "sidebar grew from #{small} to #{large} queries when employees went 3 -> 30; " \
      "that means a per-employee query crept back in"
  end

  test "observer review approvals are not queried per employee" do
    seed_employees(3)
    seed_observer_approvals
    sign_in @admin, scope: :user
    get "/settings"
    small = measure("/settings")

    seed_employees(27, offset: 3)
    seed_observer_approvals
    large = measure("/settings")

    assert_response :success
    assert_operator large, :<=, small + 2,
      "observer approval checks scaled with employee count (#{small} -> #{large})"
  end

  test "the L1 listing does not issue a query per row" do
    seed_employees(3)
    sign_in @admin, scope: :user
    get "/employee_details/l1"
    assert_response :success
    small = measure("/employee_details/l1")

    seed_employees(27, offset: 3)
    large = measure("/employee_details/l1")

    assert_response :success
    assert_operator large, :<=, small + 2,
      "L1 listing scaled with employee count (#{small} -> #{large})"
  end

  test "an observer listing does not issue a query per row" do
    seed_employees(3)
    sign_in @admin, scope: :user
    get "/employee_details/observer_1"
    assert_response :success
    small = measure("/employee_details/observer_1")

    seed_employees(27, offset: 3)
    large = measure("/employee_details/observer_1")

    assert_response :success
    assert_operator large, :<=, small + 2,
      "observer listing scaled with employee count (#{small} -> #{large})"
  end

  test "the quarterly PLI excel export does not issue a query per row" do
    seed_employees(3)
    sign_in @admin, scope: :user
    get "/employee_details/export_quarterly_pli_xlsx"
    assert_response :success
    small = measure("/employee_details/export_quarterly_pli_xlsx")

    seed_employees(27, offset: 3)
    large = measure("/employee_details/export_quarterly_pli_xlsx")

    assert_response :success
    assert_operator large, :<=, small + 2,
      "quarterly PLI export scaled with employee count (#{small} -> #{large})"
  end

  test "the observer excel export does not issue a query per row" do
    seed_employees(3)
    sign_in @admin, scope: :user
    get "/employee_details/export_observer_pli_xlsx"
    assert_response :success
    small = measure("/employee_details/export_observer_pli_xlsx")

    seed_employees(27, offset: 3)
    large = measure("/employee_details/export_observer_pli_xlsx")

    assert_response :success
    assert_operator large, :<=, small + 2,
      "observer export scaled with employee count (#{small} -> #{large})"
  end

  private

  def seed_employees(count, offset: 0)
    count.times do |i|
      index = offset + i
      employee = EmployeeDetail.create!(
        employee_name: "Scale Employee #{format('%03d', index)}",
        employee_code: "SCALEEMP#{format('%03d', index)}",
        employee_email: "scale#{index}@example.com",
        department: "Scale",
        l1_code: "SCALEADMIN",
        obs_code1: "SCALEADMIN", obs_code2: "SCALEADMIN",
        obs_code3: "SCALEADMIN", obs_code4: "SCALEADMIN"
      )

      @activities.each do |activity|
        detail = UserDetail.create!(
          department: @department, activity: activity, employee_detail: employee,
          financial_year: "2026-2027",
          **MONTHS.to_h { |month| [ month.to_sym, "100" ] }
        )
        MONTHS.each do |month|
          Achievement.create!(user_detail: detail, month: month, achievement: "90")
        end
      end
    end
  end

  def seed_observer_approvals
    EmployeeDetail.where("employee_code LIKE 'SCALEEMP%'").find_each do |employee|
      %w[april may june].each do |month|
        %w[obs_code1 obs_code2 obs_code3 obs_code4].each do |level|
          ObserverPliReview.find_or_create_by!(
            employee_detail: employee, financial_year: "2026-2027", quarter: "Q1",
            month: month, observer_level: level
          ) { |review| review.status = "approved" }
        end
      end
    end
  end

  # Each measurement starts from a fresh session so one request's session state
  # cannot change the next request's query count.
  def measure(path)
    reset!
    sign_in @admin, scope: :user
    count_queries { get path }
  end

  def count_queries
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      count += 1 unless payload[:name].to_s =~ /SCHEMA|TRANSACTION/
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end

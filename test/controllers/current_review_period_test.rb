require_relative "../../config/environment"
require "minitest/autorun"
require "active_support/testing/time_helpers"

class CurrentReviewPeriodTest < Minitest::Test
  include ActiveSupport::Testing::TimeHelpers

  def controller_for(admin: false, hod: false, **params)
    controller = EmployeeDetailsController.new
    user = Struct.new(:admin?, :hod?).new(admin, hod)
    controller.define_singleton_method(:current_user) { user }
    controller.define_singleton_method(:action_name) { "l1" }
    controller.define_singleton_method(:render) { |**options| @rejection = options }
    controller.params = ActionController::Parameters.new(params)
    controller
  end

  def test_previous_quarter_stays_open_for_first_month_then_rolls_over
    {
      "2026-03-31" => ["Q4", "2025-2026"],
      "2026-04-01" => ["Q4", "2025-2026"],
      "2026-04-30" => ["Q4", "2025-2026"],
      "2026-05-01" => ["Q1", "2026-2027"],
      "2026-06-30" => ["Q1", "2026-2027"],
      "2026-07-01" => ["Q1", "2026-2027"],
      "2026-07-31" => ["Q1", "2026-2027"],
      "2026-08-01" => ["Q2", "2026-2027"],
      "2026-09-30" => ["Q2", "2026-2027"],
      "2026-10-01" => ["Q2", "2026-2027"],
      "2026-10-31" => ["Q2", "2026-2027"],
      "2026-11-01" => ["Q3", "2026-2027"],
      "2026-12-31" => ["Q3", "2026-2027"],
      "2027-01-01" => ["Q3", "2026-2027"],
      "2027-01-31" => ["Q3", "2026-2027"],
      "2027-02-01" => ["Q4", "2026-2027"],
      "2027-04-30" => ["Q4", "2026-2027"],
      "2027-05-01" => ["Q1", "2027-2028"]
    }.each do |date, (quarter, year)|
      travel_to(Time.zone.parse(date)) do
        controller = controller_for
        controller.send(:restrict_user_review_period)
        assert_equal quarter, controller.params[:quarter]
        assert_equal quarter, controller.params[:selected_quarter]
        assert_equal year, controller.params[:financial_year]
        assert_equal [quarter], controller.send(:available_review_quarters)
        assert_empty controller.send(:build_monthly_employee_data, [], approval_level: "l1")
        controller.send(:prepare_review_filters, [])
        assert_equal controller.send(:get_quarter_months, quarter), controller.instance_variable_get(:@month_options).map(&:last)
        assert_equal [year], controller.instance_variable_get(:@financial_year_options)
      end
    end
  end

  def test_users_cannot_request_other_periods
    travel_to(Time.zone.parse("2026-10-22")) do
      [ {quarter: "Q3"}, {selected_quarter: "Q1"}, {month: "october"},
        {selected_month: "april"}, {financial_year: "2025-2026"},
        {selected_financial_year: "2025-2026"} ].each do |params|
        controller = controller_for(**params)
        controller.send(:restrict_user_review_period)
        assert_equal :forbidden, controller.instance_variable_get(:@rejection)[:status]
      end
    end
  end

  def test_october_accepts_previous_quarter_requests
    travel_to(Time.zone.parse("2026-10-22")) do
      controller = controller_for(quarter: "Q2", month: "september", financial_year: "2026-2027")
      controller.send(:restrict_user_review_period)
      assert_nil controller.instance_variable_get(:@rejection)
      assert_equal "Q2", controller.params[:quarter]
      assert_equal "september", controller.params[:month]
    end
  end

  def test_hod_keeps_all_quarters
    controller = controller_for(hod: true, quarter: "Q1")
    controller.send(:restrict_user_review_period)
    assert_equal "Q1", controller.params[:quarter]
    assert_equal %w[Q1 Q2 Q3 Q4], controller.send(:available_review_quarters)
  end

  def test_admin_keeps_all_quarters_and_requested_period
    controller = controller_for(admin: true, quarter: "Q2", financial_year: "2025-2026")
    controller.send(:restrict_user_review_period)
    assert_equal "Q2", controller.params[:quarter]
    assert_equal "2025-2026", controller.params[:financial_year]
    assert_equal %w[Q1 Q2 Q3 Q4], controller.send(:available_review_quarters)
    assert_nil controller.instance_variable_get(:@rejection)
  end
end

require_relative "../../config/environment"
require "minitest/autorun"
require "ostruct"

class UserDataExportTest < Minitest::Test
  def test_export_uses_saved_final_pli_and_monthly_summary_remarks
    check_export(95, "95.00%")
  end

  def test_zero_final_pli_is_preserved
    check_export(0, "0.00%")
  end

  def test_unsaved_final_pli_does_not_export_calculated_average
    check_export(nil, "-")
  end

  def test_all_quarters_use_the_selected_months
    %w[Q2 Q3 Q4].each { |quarter| check_export(95, "95.00%", quarter: quarter) }
  end

  def check_export(final_percentage, expected_percentage, quarter: "Q1")
    months = UserDetailsController::QUARTER_MONTHS.fetch(quarter)
    old = OpenStruct.new(l1_remarks: "Old KRI comment", updated_at: Time.utc(2026, 6, 1))
    latest = OpenStruct.new(l1_remarks: "Actual monthly L1", updated_at: Time.utc(2026, 6, 2))
    details = [old, latest].each_with_index.map do |remark, id|
      OpenStruct.new(id: id, financial_year: "2026-2027", activity: Object.new,
        **months.to_h { |month| [month.to_sym, "100"] },
        achievements: months.each_with_index.map do |month, index|
          OpenStruct.new(month: month, achievement: ((index + 1) * 25).to_s, achievement_remark: OpenStruct.new(l1_remarks: "#{month}: #{remark.l1_remarks}", updated_at: remark.updated_at))
        end)
    end
    review = OpenStruct.new(financial_year: "2026-2027", quarter: quarter, status: "approved",
      final_percentage: final_percentage, final_remarks: "Actual quarterly decision")
    employee = OpenStruct.new(id: 451, employee_code: "1025", employee_name: "Sharad",
      user_details: details, quarterly_pli_reviews: [review])
    employee.define_singleton_method(:observer_assigned?) { |level| true }
    relation = Object.new
    relation.define_singleton_method(:order) { |*| self }
    relation.define_singleton_method(:to_a) { [employee] }
    controller = UserDetailsController.new
    controller.params = ActionController::Parameters.new(quarter: quarter)
    controller.define_singleton_method(:current_user) { OpenStruct.new(hod?: true) }
    controller.define_singleton_method(:set_financial_year_context) { @selected_financial_year = "2026-2027" }
    controller.define_singleton_method(:send_data) { |data, **| @export_data = data }
    EmployeeDetail.stub(:includes, relation) do
      ObserverPliReview.stub(:prime_cache, nil) do
        observer_lookup = ->(id, year, q, month, level) {
          assert_equal [451, "2026-2027", quarter], [id, year, q]
          OpenStruct.new(final_remarks: "#{month}: #{level} final")
        }
        ObserverPliReview.stub(:cached_find, observer_lookup) do
          controller.export_user_data_xlsx
        end
      end
    end
    Zip::File.open_buffer(controller.instance_variable_get(:@export_data)) do |zip|
      doc = Nokogiri::XML(zip.read("xl/worksheets/sheet1.xml"))
      doc.remove_namespaces!
      values = doc.xpath('//row[@r="2"]/c').map { |cell| cell.xpath('.//t').map(&:text).join }
      months.each_with_index do |month, index|
        offset = 9 + index * 6
        assert_equal format("%.2f%%", (index + 1) * 25), values[offset]
        (1..4).each do |number|
          assert_equal "#{month}: obs_code#{number} final", values[offset + number]
        end
        assert_equal "#{month}: Actual monthly L1", values[offset + 5]
      end
      assert_equal "50.00%", values[-3]
      assert_equal expected_percentage, values[-2]
      assert_equal "Actual quarterly decision", values[-1]
      refute_includes values, "Old KRI comment"
    end
  end
end

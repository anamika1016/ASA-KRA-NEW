require "test_helper"

class EmployeeDetailTest < ActiveSupport::TestCase
  test "placeholder observer codes are unassigned and normalized on save" do
    employee = EmployeeDetail.new(obs_code1: " - ", obs_code2: "N/A", obs_code3: " 1621 ")

    assert_not employee.observer_assigned?(:obs_code1)
    assert_not employee.observer_assigned?(:obs_code2)
    assert employee.observer_assigned?(:obs_code3)

    employee.validate

    assert_nil employee.obs_code1
    assert_nil employee.obs_code2
    assert_equal "1621", employee.obs_code3
  end
end

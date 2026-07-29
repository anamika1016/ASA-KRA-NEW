require "test_helper"

class AbilityTest < ActiveSupport::TestCase
  test "PAPL095 can read L1 employee delegated to code 840" do
    user = User.new(employee_code: "PAPL095", email: "papl095@example.com", role: "employee")
    employee = EmployeeDetail.new(l1_code: "840", status: "pending")

    assert Ability.new(user).can?(:read, employee)
  end

  test "PAPL095 can read L1 employee delegated to code 002 with nil status" do
    user = User.new(employee_code: "PAPL095", email: "papl095@example.com", role: "employee")
    employee = EmployeeDetail.new(l1_code: "002", status: nil)

    assert Ability.new(user).can?(:read, employee)
  end

  test "unrelated login cannot read delegated L1 employee" do
    user = User.new(employee_code: "EMP001", email: "employee@example.com", role: "employee")
    employee = EmployeeDetail.new(l1_code: "840", status: "pending")

    assert_not Ability.new(user).can?(:read, employee)
  end
end

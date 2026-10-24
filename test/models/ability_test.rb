require "test_helper"

class AbilityTest < ActiveSupport::TestCase
  test "employee can read own KRA with differing code case and whitespace" do
    user = User.new(employee_code: "PAPL454", email: "login@example.com", role: "employee")
    employee = EmployeeDetail.new(employee_code: " papl454 ", employee_email: "other@example.com")

    assert Ability.new(user).can?(:read, employee)
  end

  test "employee can read own KRA with differing email case and whitespace" do
    user = User.new(employee_code: "PAPL454", email: "employee@example.com", role: "employee")
    employee = EmployeeDetail.new(employee_code: "OTHER", employee_email: " Employee@Example.COM ")

    assert Ability.new(user).can?(:read, employee)
  end

  test "blank identities do not grant access to unrelated employees" do
    user = User.new(employee_code: nil, email: "login@example.com", role: "employee")
    employee = EmployeeDetail.new(employee_code: nil, employee_email: "other@example.com", l2_code: nil, l2_employer_name: nil, status: "l1_approved")

    assert_not Ability.new(user).can?(:read, employee)
  end

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

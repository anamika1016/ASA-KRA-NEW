require "test_helper"

class EmployeeDetailShowAccessTest < ActiveSupport::TestCase
  test "L1 can open details for an assignment stored under their linked name" do
    controller, employee = show_controller_for(" Anurag Patel ")

    assert controller.send(:l1_employee_scope_for_current_user).where(id: employee.id).exists?
    controller.show

    assert controller.instance_variable_get(:@detail_prepared)
    assert_nil controller.instance_variable_get(:@access_redirect)
  end

  test "L1 cannot open details for an unrelated employee" do
    controller, = show_controller_for("Another Reviewer")

    controller.show

    assert_not controller.instance_variable_get(:@detail_prepared)
    assert controller.instance_variable_get(:@access_redirect)
  end

  test "name assignment does not grant L1 access when the menu is disabled" do
    controller, = show_controller_for("Anurag Patel")
    controller.define_singleton_method(:menu_access_enabled?) { |_key| false }

    controller.show

    assert_not controller.instance_variable_get(:@detail_prepared)
    assert controller.instance_variable_get(:@access_redirect)
  end

  private

  def show_controller_for(reviewer_name)
    user = User.new(employee_code: "939", email: "reviewer@example.com", role: "employee")
    linked = EmployeeDetail.new(employee_code: "939", employee_name: "Anurag Patel", employee_email: user.email)
    employee = EmployeeDetail.create!(employee_code: "SHOW-ACCESS", employee_name: "Reviewed Employee", l1_employer_name: reviewer_name)
    controller = EmployeeDetailsController.new
    controller.params = ActionController::Parameters.new(id: employee.id)
    controller.define_singleton_method(:current_user) { user }
    controller.define_singleton_method(:portal_employee_detail_for) { |_user| linked }
    controller.define_singleton_method(:menu_access_enabled?) { |_key| true }
    controller.define_singleton_method(:prepare_employee_detail_show) { @detail_prepared = true }
    controller.define_singleton_method(:redirect_to) { |*args, **kwargs| @access_redirect = [ args, kwargs ] }
    [ controller, employee ]
  end
end

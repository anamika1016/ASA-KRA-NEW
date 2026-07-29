require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "PAPL095 reviewer identity includes delegated employee codes" do
    user = User.new(employee_code: " PAPL095 ")

    assert_equal %w[papl095 840 002], user.reviewer_identity_codes
  end

  test "ordinary reviewer identity only includes its own employee code" do
    user = User.new(employee_code: " EMP001 ")

    assert_equal %w[emp001], user.reviewer_identity_codes
  end
end

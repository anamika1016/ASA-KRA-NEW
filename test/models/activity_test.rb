require "test_helper"

class ActivityTest < ActiveSupport::TestCase
  test "cleans spreadsheet html markup from activity name before save" do
    activity = activities(:one)
    activity.update!(activity_name: "<html><b>Sausar</b> - Day to day coordination</html>")

    assert_equal "Sausar - Day to day coordination", activity.reload.activity_name
  end

  test "cleans spreadsheet bold markdown artifacts" do
    activity = activities(:one)
    activity.update!(activity_name: "**Key result indicators**")

    assert_equal "Key result indicators", activity.reload.activity_name
  end
end

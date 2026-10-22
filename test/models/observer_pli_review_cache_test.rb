require "test_helper"

# The review screens used to ask the database once per rendered row whether an
# observer had approved a month. Those lookups now go through a request-scoped
# cache, so these tests pin down two things: the cached answers match what a
# direct query would return, and repeated lookups cost a single query.
class ObserverPliReviewCacheTest < ActiveSupport::TestCase
  setup do
    Current.reset
    @employee = EmployeeDetail.create!(
      employee_name: "Cache Probe",
      employee_code: "CACHE001",
      department: "HR",
      obs_code1: "OBS1",
      obs_code2: "OBS2"
    )
    @other_employee = EmployeeDetail.create!(
      employee_name: "Cache Probe Two",
      employee_code: "CACHE002",
      department: "HR",
      obs_code1: "OBS1"
    )

    @approved = ObserverPliReview.create!(
      employee_detail: @employee, financial_year: "2026-2027",
      quarter: "Q2", month: "july", observer_level: "obs_code1",
      status: "approved", final_remarks: "Looks good"
    )
    ObserverPliReview.create!(
      employee_detail: @employee, financial_year: "2026-2027",
      quarter: "Q2", month: "august", observer_level: "obs_code1",
      status: "pending"
    )
    ObserverPliReview.create!(
      employee_detail: @employee, financial_year: "2026-2027",
      quarter: "Q2", month: "september", observer_level: "obs_code2",
      status: "returned"
    )
    Current.reset
  end

  teardown { Current.reset }

  # Every combination the screens ask about must agree with a direct query.
  test "cached_approved? matches a direct exists? for every combination" do
    months = %w[july august september october]
    levels = %w[obs_code1 obs_code2 obs_code3]
    years = [ "2026-2027", "2027-2028" ]

    [ @employee, @other_employee ].each do |employee|
      years.each do |year|
        %w[Q1 Q2].each do |quarter|
          months.each do |month|
            levels.each do |level|
              expected = ObserverPliReview.exists?(
                employee_detail: employee, financial_year: year, quarter: quarter,
                month: month, observer_level: level, status: "approved"
              )
              actual = ObserverPliReview.cached_approved?(employee.id, year, quarter, month, level)

              assert_equal expected, actual,
                "mismatch for #{employee.employee_code} #{year} #{quarter} #{month} #{level}"
            end
          end
        end
      end
    end
  end

  test "cached_find returns the same row a direct find_by would" do
    expected = ObserverPliReview.find_by(
      employee_detail: @employee, financial_year: "2026-2027",
      quarter: "Q2", month: "july", observer_level: "obs_code1"
    )

    assert_equal expected, ObserverPliReview.cached_find(@employee.id, "2026-2027", "Q2", "july", "obs_code1")
    assert_nil ObserverPliReview.cached_find(@employee.id, "2026-2027", "Q2", "july", "obs_code4")
  end

  # A NULL month must behave exactly as it does in SQL: `month = ''` never
  # matches NULL, and only a nil search term does.
  test "a review with no month matches SQL NULL semantics" do
    ObserverPliReview.create!(
      employee_detail: @employee, financial_year: "2026-2027",
      quarter: "Q3", month: nil, observer_level: "obs_code1", status: "approved"
    )
    Current.reset

    [ nil, "", "october" ].each do |month|
      expected = ObserverPliReview.exists?(
        employee_detail: @employee, financial_year: "2026-2027", quarter: "Q3",
        month: month, observer_level: "obs_code1", status: "approved"
      )
      actual = ObserverPliReview.cached_approved?(@employee.id, "2026-2027", "Q3", month, "obs_code1")

      assert_equal expected, actual, "NULL month handling differs for month=#{month.inspect}"
    end
  end

  # Postgres treats NULLs as distinct, so the unique index allows several
  # NULL-month rows. exists? looks at all of them, so the cache must too.
  test "approval is found even when an earlier NULL month row is not approved" do
    ObserverPliReview.create!(
      employee_detail: @employee, financial_year: "2026-2027",
      quarter: "Q4", month: nil, observer_level: "obs_code1", status: "pending"
    )
    ObserverPliReview.create!(
      employee_detail: @employee, financial_year: "2026-2027",
      quarter: "Q4", month: nil, observer_level: "obs_code1", status: "approved"
    )
    Current.reset

    expected = ObserverPliReview.exists?(
      employee_detail: @employee, financial_year: "2026-2027", quarter: "Q4",
      month: nil, observer_level: "obs_code1", status: "approved"
    )

    assert expected, "fixture should have an approved row"
    assert_equal expected, ObserverPliReview.cached_approved?(@employee.id, "2026-2027", "Q4", nil, "obs_code1")
  end

  test "one financial year's cache entry does not answer for another" do
    ObserverPliReview.create!(
      employee_detail: @employee, financial_year: "2027-2028", quarter: "Q2",
      month: "july", observer_level: "obs_code1", status: "pending"
    )
    Current.reset

    assert ObserverPliReview.cached_approved?(@employee.id, "2026-2027", "Q2", "july", "obs_code1")
    assert_not ObserverPliReview.cached_approved?(@employee.id, "2027-2028", "Q2", "july", "obs_code1")
    assert_nil ObserverPliReview.cached_find(@employee.id, "2028-2029", "Q2", "july", "obs_code1")
  end

  test "a non-approved review is not reported as approved" do
    assert_not ObserverPliReview.cached_approved?(@employee.id, "2026-2027", "Q2", "august", "obs_code1")
    assert_not ObserverPliReview.cached_approved?(@employee.id, "2026-2027", "Q2", "september", "obs_code2")
  end

  test "many lookups for one employee cost a single query" do
    queries = count_queries do
      12.times do
        ObserverPliReview.cached_approved?(@employee.id, "2026-2027", "Q2", "july", "obs_code1")
        ObserverPliReview.cached_approved?(@employee.id, "2026-2027", "Q2", "august", "obs_code2")
      end
    end

    assert_equal 1, queries, "expected the employee's reviews to be loaded once"
  end

  test "prime_cache loads many employees in one query and serves them from memory" do
    ids = [ @employee.id, @other_employee.id ]

    primed = count_queries { ObserverPliReview.prime_cache(ids, "2026-2027") }
    assert_equal 1, primed

    served = count_queries do
      ids.each do |id|
        ObserverPliReview.cached_approved?(id, "2026-2027", "Q2", "july", "obs_code1")
      end
    end
    assert_equal 0, served, "primed employees should not hit the database again"
  end

  test "prime_cache only fetches employees that are not cached yet" do
    ObserverPliReview.prime_cache([ @employee.id ], "2026-2027")

    assert_equal 0, count_queries { ObserverPliReview.prime_cache([ @employee.id ], "2026-2027") }
    assert_equal 1, count_queries { ObserverPliReview.prime_cache([ @other_employee.id ], "2026-2027") }
  end

  test "saving a review drops the cache so later reads see the new status" do
    assert ObserverPliReview.cached_approved?(@employee.id, "2026-2027", "Q2", "july", "obs_code1")

    @approved.update!(status: "returned")

    assert_not ObserverPliReview.cached_approved?(@employee.id, "2026-2027", "Q2", "july", "obs_code1")
  end

  test "destroying a review drops the cache" do
    assert ObserverPliReview.cached_approved?(@employee.id, "2026-2027", "Q2", "july", "obs_code1")

    @approved.destroy!

    assert_not ObserverPliReview.cached_approved?(@employee.id, "2026-2027", "Q2", "july", "obs_code1")
  end

  private

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

class AddNormalizedLookupIndexes < ActiveRecord::Migration[8.0]
  # Sidebar and observer screens look employees up by normalised codes, e.g.
  # LOWER(TRIM(COALESCE(obs_code1, ''))). The plain column indexes cannot serve
  # those expressions, so every check fell back to a sequential scan.
  def change
    %w[obs_code1 obs_code2 obs_code3 obs_code4].each do |column|
      add_index :employee_details,
                "lower(trim(coalesce(#{column}, '')))",
                name: "index_employee_details_on_normalized_#{column}",
                if_not_exists: true
    end

    # Postgres only uses an expression index when the expression matches the
    # query exactly, so index each form the app actually issues.
    add_index :employee_details, "lower(trim(employee_code))",
              name: "index_employee_details_on_lower_trim_employee_code", if_not_exists: true
    add_index :employee_details, "lower(trim(employee_email))",
              name: "index_employee_details_on_lower_trim_employee_email", if_not_exists: true
    add_index :employee_details, "lower(employee_code)",
              name: "index_employee_details_on_lower_employee_code", if_not_exists: true
    add_index :employee_details, "lower(employee_email)",
              name: "index_employee_details_on_lower_employee_email", if_not_exists: true
    add_index :employee_details, "lower(employee_name)",
              name: "index_employee_details_on_lower_employee_name", if_not_exists: true
  end
end

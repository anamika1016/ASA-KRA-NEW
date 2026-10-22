module ApplicationHelper
  OBSERVER_LEVELS = %w[obs_code1 obs_code2 obs_code3 obs_code4].freeze
  SPREADSHEET_ERROR_VALUES = %w[#DIV/0! #N/A #NAME? #NULL! #NUM! #REF! #VALUE!].freeze
  MONTH_SHORT_LABELS = {
    "april" => "APR",
    "may" => "MAY",
    "june" => "JUN",
    "july" => "JUL",
    "august" => "AUG",
    "september" => "SEP",
    "october" => "OCT",
    "november" => "NOV",
    "december" => "DEC",
    "january" => "JAN",
    "february" => "FEB",
    "march" => "MAR"
  }.freeze

  # Same month-to-quarter mapping as quarter_name_for_month, for use inside SQL.
  SIDEBAR_QUARTER_SQL = <<~SQL.squish.freeze
    CASE
      WHEN LOWER(achievements.month) IN ('april','may','june') THEN 'Q1'
      WHEN LOWER(achievements.month) IN ('july','august','september') THEN 'Q2'
      WHEN LOWER(achievements.month) IN ('october','november','december') THEN 'Q3'
      WHEN LOWER(achievements.month) IN ('january','february','march') THEN 'Q4'
    END
  SQL

  def current_user_detail
    current_user&.user_detail
  end

  def asset_to_base64(asset_name)
    path = Rails.root.join("app", "assets", "images", asset_name)
    if File.exist?(path)
      content = File.binread(path)
      ext = File.extname(asset_name).downcase.delete(".")
      mime_type = case ext
      when "jpg", "jpeg" then "image/jpeg"
      when "png" then "image/png"
      else "image/#{ext}"
      end
      "data:#{mime_type};base64,#{Base64.strict_encode64(content)}"
    else
      Rails.logger.error "ASSET NOT FOUND: #{path}"
      ""
    end
  end

  def annual_target_fy_label(financial_year)
    year = financial_year.to_s.presence
    start_year, end_year = year.to_s.split("-", 2)

    if start_year.present? && end_year.present?
      "Annual target FY #{start_year}-#{end_year.last(2)}"
    else
      "Annual target FY"
    end
  end

  def short_month_label(month)
    MONTH_SHORT_LABELS[month.to_s.downcase] || month.to_s.upcase
  end

  def annual_target_display(activity_or_value, unit = nil)
    value = if activity_or_value.respond_to?(:annual_target_fy)
      unit ||= activity_or_value.respond_to?(:unit) ? activity_or_value.unit : nil
      activity_or_value.annual_target_fy
    else
      activity_or_value
    end

    cleaned_value = clean_spreadsheet_display_value(value)
    return "-" if cleaned_value.blank?

    if unit.to_s.strip == "%" && cleaned_value.match?(/\A1(?:\.0+)?\z/)
      return "100%"
    end

    cleaned_value.sub(/\A(-?\d+)\.0+\z/, "\\1")
  end

  def clean_spreadsheet_display_value(value)
    return nil if value.nil?

    cleaned_value = Activity.clean_spreadsheet_markup(value)
    return nil if cleaned_value.blank?
    return nil if SPREADSHEET_ERROR_VALUES.include?(cleaned_value.upcase)

    cleaned_value
  end

  def activity_name_display(activity_or_name)
    value = activity_or_name.respond_to?(:activity_name) ? activity_or_name.activity_name : activity_or_name

    clean_spreadsheet_display_value(value).presence || "N/A"
  end

  def target_display_value(value)
    clean_spreadsheet_display_value(value).presence || "-"
  end

  def target_value_present?(value)
    cleaned_value = clean_spreadsheet_display_value(value)
    cleaned_value.present? && cleaned_value != "0"
  end

  def l2_reviewer_assigned?(employee_detail)
    false
  end

  def observer_assigned?(employee_detail, observer_level)
    return false if employee_detail.blank?
    return false unless OBSERVER_LEVELS.include?(observer_level.to_s)

    employee_detail.observer_assigned?(observer_level)
  end

  def observer_level_number(observer_level)
    observer_level.to_s.gsub(/\D/, "").to_i
  end

  def observer_column_label(observer_level)
    "OBS#{observer_level_number(observer_level)}"
  end

  def observer_menu_title_for(observer_level)
    "Observer Menu #{observer_level_number(observer_level)}"
  end

  def observer_remark_column(observer_level)
    "#{observer_level}_remarks".to_sym
  end

  def observer_levels_for_display(employee_detail)
    assigned_levels = OBSERVER_LEVELS.select { |level| observer_assigned?(employee_detail, level) }

    if defined?(@observer_context) && @observer_context && @observer_level.present?
      assigned_levels & [ @observer_level ]
    else
      assigned_levels
    end
  end

  def observer_assigned_for_display?(employee_detail, observer_level)
    observer_assigned?(employee_detail, observer_level)
  end

  def portal_employee_detail_for(user = current_user)
    return if user.blank?

    cache = (@portal_employee_detail_cache ||= {})
    return cache[user.id] if cache.key?(user.id)

    cache[user.id] = user.employee_detail ||
      EmployeeDetail.find_by("LOWER(employee_email) = ?", user.email.to_s.downcase) ||
      EmployeeDetail.find_by("LOWER(employee_code) = ?", user.employee_code.to_s.downcase)
  end

  def resolved_observer_identity_code(user = current_user)
    return nil if user.blank?

    code = user.employee_code.to_s.strip.presence
    code ||= portal_employee_detail_for(user)&.employee_code.to_s.strip.presence
    code
  end

  def observer_level_assigned_to_user?(observer_level, user = current_user)
    return false if user.blank?
    return true if user.admin? || user.hod?
    return false unless OBSERVER_LEVELS.include?(observer_level.to_s)

    menu_key = "observer_#{OBSERVER_LEVELS.index(observer_level.to_s) + 1}"
    return false unless menu_access_enabled?(menu_key, user)

    code = resolved_observer_identity_code(user)
    return false if code.blank?

    reviewer_codes = user.reviewer_identity_codes

    EmployeeDetail.where(
      "LOWER(TRIM(COALESCE(#{observer_level}, ''))) IN (:reviewer_codes) OR LOWER(TRIM(COALESCE(#{observer_level}, ''))) LIKE :code_prefix",
      reviewer_codes: reviewer_codes,
      code_prefix: "#{code.downcase}%"
    ).exists?
  end

  def observer_levels_for_user(user = current_user)
    return [] if user.blank?
    return OBSERVER_LEVELS if user.admin? || user.hod?

    OBSERVER_LEVELS.select { |level| observer_level_assigned_to_user?(level, user) }
  end

  def observer_levels_for_current_user
    observer_levels_for_user(current_user)
  end

  # Sidebar visibility is based only on assignment. Employee access settings
  # block the destination action, but never make the menu disappear.
  def observer_levels_for_sidebar(user = current_user)
    return [] if user.blank?
    return OBSERVER_LEVELS if user.admin? || user.hod?

    code = resolved_observer_identity_code(user).to_s.strip.downcase
    reviewer_codes = user.reviewer_identity_codes
    return [] if code.blank?

    OBSERVER_LEVELS.select do |observer_level|
      EmployeeDetail.where(
        "LOWER(TRIM(COALESCE(#{observer_level}, ''))) IN (:reviewer_codes) OR LOWER(TRIM(COALESCE(#{observer_level}, ''))) LIKE :prefix",
        reviewer_codes: reviewer_codes,
        prefix: "#{code}%"
      ).exists?
    end
  end

  def has_observer_pli_responsibilities?(observer_level = nil)
    return observer_levels_for_user(current_user).any? if observer_level.blank?

    observer_level_assigned_to_user?(observer_level, current_user)
  end

  def sidebar_menu_active?(menu_key)
    SidebarMenuSetting.active_for?(menu_key)
  end

  def employee_sidebar_menu_active?(menu_key)
    employee_menu_access_enabled?(menu_key)
  end

  def observer_menu_active?(observer_level)
    return true if current_page?(observer_pli_index_path(observer_level))
    return false unless controller_name == "employee_details"

    case action_name
    when "observer_1", "observer_2", "observer_3", "observer_4"
      OBSERVER_LEVELS[action_name.gsub(/\D/, "").to_i - 1] == observer_level
    when "observer_pli_detail"
      params[:observer_level].to_s == observer_level
    else
      false
    end
  end

  def observer_employee_name_for(employee_detail, observer_level)
    code = employee_detail.public_send(observer_level).to_s.strip
    return nil if code.blank?

    EmployeeDetail.where("LOWER(employee_code) = ?", code.downcase).pick(:employee_name)
  end

  def observer_pli_index_path(observer_level, **options)
    case observer_level.to_s
    when "obs_code2" then observer_2_employee_details_path(options)
    when "obs_code3" then observer_3_employee_details_path(options)
    when "obs_code4" then observer_4_employee_details_path(options)
    else observer_1_employee_details_path(options)
    end
  end

  # The sidebar only draws a dot, so it needs "is there at least one?". Letting
  # the database find the unapproved rows avoids pulling every employee's user
  # details and achievements into memory on every page render. The Ruby checks
  # below still decide, so the answer matches observer_pending_reviews_count.
  def observer_pending_reviews?(observer_level)
    return false unless observer_level_assigned_to_user?(observer_level, current_user)

    scope = observer_pending_count_scope(observer_level)
    return false if scope.nil?

    financial_year = sidebar_current_financial_year

    observer_pending_candidates(scope, observer_level, financial_year).find_each(batch_size: 25) do |achievement|
      next if achievement.achievement.blank?

      employee = achievement.user_detail&.employee_detail
      next unless observer_assigned?(employee, observer_level)
      next if quarter_name_for_month(achievement.month.to_s.downcase).blank?

      return true
    end

    false
  rescue StandardError
    false
  end

  # Achievements that are submitted, belong to the observer's employees and have
  # no approved review yet. Mirrors the key comparison the count version makes:
  # the stored review month is matched against the lowercased achievement month.
  def observer_pending_candidates(employee_scope, observer_level, financial_year)
    Achievement
      .joins(user_detail: :employee_detail)
      .merge(employee_scope.unscope(:order))
      .where(user_details: { financial_year: financial_year })
      .where.not(achievements: { achievement: [ nil, "" ] })
      .where("LOWER(achievements.month) IN (?)", MONTH_SHORT_LABELS.keys)
      .where(
        "NOT EXISTS (
           SELECT 1 FROM observer_pli_reviews opr
           WHERE opr.employee_detail_id = employee_details.id
             AND opr.financial_year = :financial_year
             AND opr.quarter = #{SIDEBAR_QUARTER_SQL}
             AND opr.month = LOWER(achievements.month)
             AND opr.observer_level = :observer_level
             AND opr.status = 'approved')",
        financial_year: financial_year,
        observer_level: observer_level
      )
      .includes(user_detail: :employee_detail)
  end

  def quarterly_pli_pending_reviews?
    quarterly_pli_pending_reviews_count.positive?
  end

  def quarterly_pli_pending_reviews_count
    return 0 unless current_user&.hod? || current_user&.admin? || l1_or_l2_reviewer_for_any_employee?

    employees = quarterly_pli_employees_for_pending_count
    return 0 if employees.empty?

    employee_ids = employees.map(&:id)
    ObserverPliReview.prime_cache(employee_ids, sidebar_current_financial_year)
    approved_keys = QuarterlyPliReview
      .where(employee_detail_id: employee_ids, financial_year: sidebar_current_financial_year, status: "approved")
      .pluck(:employee_detail_id, :financial_year, :quarter)

    pending_keys = []
    employees.each do |employee|
      details = employee.user_details.select { |detail| detail.financial_year.to_s == sidebar_current_financial_year && detail.activity.present? }
      next if details.empty?

      %w[Q1 Q2 Q3 Q4].each do |quarter|
        next unless quarter_ready_for_sidebar_pli?(employee, details, quarter)

        key = [ employee.id, sidebar_current_financial_year, quarter ]
        pending_keys << key unless approved_keys.include?(key)
      end
    end

    pending_keys.uniq.size
  rescue StandardError
    0
  end

  def observer_pending_reviews_count(observer_level)
    return 0 unless observer_level_assigned_to_user?(observer_level, current_user)

    employees = observer_employees_for_pending_count(observer_level)
    return 0 if employees.none?

    employee_ids = employees.map(&:id)
    approved_keys = ObserverPliReview
      .where(employee_detail_id: employee_ids, observer_level: observer_level, financial_year: sidebar_current_financial_year, status: "approved")
      .pluck(:employee_detail_id, :financial_year, :quarter, :month)
      .to_set

    pending_keys = Set.new
    employees.each do |employee|
      financial_year = sidebar_current_financial_year
      details = employee.user_details.select { |detail| detail.financial_year.to_s == financial_year }
      details.flat_map(&:achievements).each do |achievement|
        next if achievement.achievement.blank?

        month = achievement.month.to_s.downcase
        quarter = quarter_name_for_month(month)
        next if quarter.blank?
        next unless observer_month_ready_for_review?(employee, observer_level, details, month)

        key = [ employee.id, financial_year, quarter, month ]
        pending_keys.add(key) unless approved_keys.include?(key)
      end
    end

    pending_keys.size
  rescue StandardError
    0
  end

  def sidebar_current_financial_year
    start_year = Date.current.month >= 4 ? Date.current.year : Date.current.year - 1
    "#{start_year}-#{start_year + 1}"
  end

  def l1_or_l2_reviewer_for_any_employee?
    code = current_user&.employee_code.to_s.strip.downcase
    email = current_user&.email.to_s.strip.downcase
    return false if code.blank? && email.blank?

    EmployeeDetail.where(
      "(:code != '' AND (LOWER(TRIM(COALESCE(l1_code, ''))) = :code OR LOWER(TRIM(COALESCE(l2_code, ''))) = :code)) OR (:email != '' AND (LOWER(TRIM(COALESCE(l1_employer_name, ''))) = :email OR LOWER(TRIM(COALESCE(l2_employer_name, ''))) = :email))",
      code: code,
      email: email
    ).exists?
  end

  def quarterly_pli_employees_for_pending_count
    scope = EmployeeDetail.includes(user_details: [ :activity, achievements: :achievement_remark ])
    return scope.to_a if current_user.admin? || current_user.hod?

    code = current_user&.employee_code.to_s.strip.downcase
    email = current_user&.email.to_s.strip.downcase
    return [] if code.blank? && email.blank?

    scope.where(
      "(:code != '' AND (LOWER(TRIM(COALESCE(l1_code, ''))) = :code OR LOWER(TRIM(COALESCE(l2_code, ''))) = :code)) OR (:email != '' AND (LOWER(TRIM(COALESCE(l1_employer_name, ''))) = :email OR LOWER(TRIM(COALESCE(l2_employer_name, ''))) = :email))",
      code: code,
      email: email
    ).to_a
  end

  def quarter_ready_for_sidebar_pli?(employee, details, quarter)
    months = sidebar_quarter_months(quarter)
    reviewable_months = months.select { |month| submitted_target_achievements_for_month(details, month).any? }
    return false if reviewable_months.empty?

    reviewable_months.all? do |month|
      sidebar_observer_chain_approved?(employee, sidebar_current_financial_year, quarter, month) &&
        submitted_target_achievements_for_month(details, month).all? { |achievement| sidebar_l1_approved_for_pli?(achievement) }
    end
  end

  def sidebar_l1_approved_for_pli?(achievement)
    %w[l1_approved l2_approved].include?(achievement.status.to_s) ||
      achievement.achievement_remark&.l1_percentage.present? ||
      achievement.achievement_remark&.l1_remarks.present?
  end

  def sidebar_observer_chain_approved?(employee, financial_year, quarter, month)
    assigned_levels = OBSERVER_LEVELS.select { |observer_level| observer_assigned?(employee, observer_level) }
    return true if assigned_levels.empty?

    assigned_levels.all? do |observer_level|
      ObserverPliReview.cached_approved?(
        employee.id,
        financial_year,
        quarter,
        month,
        observer_level
      )
    end
  end

  def sidebar_quarter_months(quarter)
    {
      "Q1" => %w[april may june],
      "Q2" => %w[july august september],
      "Q3" => %w[october november december],
      "Q4" => %w[january february march]
    }[quarter.to_s] || []
  end

  # The sidebar asks this for every observer level, and the levels cover largely
  # the same employees. Select the ids with the unchanged scope, but build the
  # heavy user_details/achievements preload once and reuse it across levels.
  def observer_employees_for_pending_count(observer_level)
    scope = observer_pending_count_scope(observer_level)
    return [] if scope.nil?

    ids = scope.pluck(:id)
    return [] if ids.empty?

    pool = (@observer_employee_pool ||= {})
    missing = ids.reject { |id| pool.key?(id) }
    if missing.any?
      EmployeeDetail.where(id: missing).includes(user_details: :achievements).each do |employee|
        pool[employee.id] = employee
      end
    end

    ids.filter_map { |id| pool[id] }
  end

  def observer_pending_count_scope(observer_level)
    scope = EmployeeDetail.order(Arel.sql("LOWER(employee_name) ASC"))
    scope = scope.where("TRIM(COALESCE(#{observer_level}, '')) != ''")

    return scope if current_user.admin? || current_user.hod?

    code = resolved_observer_identity_code(current_user)
    return nil if code.blank?

    reviewer_codes = current_user.reviewer_identity_codes

    scope.where(
      "LOWER(TRIM(COALESCE(#{observer_level}, ''))) IN (:reviewer_codes) OR LOWER(TRIM(COALESCE(#{observer_level}, ''))) LIKE :code_prefix",
      reviewer_codes: reviewer_codes,
      code_prefix: "#{code.downcase}%"
    )
  end

  def observer_month_ready_for_review?(employee_detail, observer_level, user_details, month)
    return false unless observer_assigned?(employee_detail, observer_level)

    submitted_target_achievements_for_month(user_details, month).any?
  end

  def quarter_name_for_month(month)
    {
      "april" => "Q1", "may" => "Q1", "june" => "Q1",
      "july" => "Q2", "august" => "Q2", "september" => "Q2",
      "october" => "Q3", "november" => "Q3", "december" => "Q3",
      "january" => "Q4", "february" => "Q4", "march" => "Q4"
    }[month.to_s.downcase]
  end

  def submitted_target_achievements_for_month(user_details, month)
    user_details.flat_map(&:achievements).select do |achievement|
      achievement.month.to_s.downcase == month.to_s.downcase && achievement.achievement.present?
    end
  end

  def manager_remarks_column_label(level, _month_name = nil)
    "#{level} RM"
  end

  def employee_remarks_column_label(_month = nil)
    "EMP REMARKS"
  end
end

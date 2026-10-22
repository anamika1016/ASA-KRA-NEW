# Request-scoped cache. ActiveSupport::CurrentAttributes is reset by Rails
# before every request, so these memos never leak between requests.
class Current < ActiveSupport::CurrentAttributes
  attribute :sidebar_menu_settings
  attribute :employee_sidebar_accesses
  attribute :observer_pli_reviews
end

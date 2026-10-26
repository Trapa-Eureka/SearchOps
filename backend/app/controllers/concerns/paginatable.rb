module Paginatable
  extend ActiveSupport::Concern

  DEFAULT_PER_PAGE = 25
  MAX_PER_PAGE = 100

  private

  # Offset pagination. Invalid or out-of-range values fall back to defaults
  # instead of failing, and per_page is capped to bound response size.
  def paginate(scope)
    page = positive_integer(params[:page]) || 1
    per_page = [ positive_integer(params[:per_page]) || DEFAULT_PER_PAGE, MAX_PER_PAGE ].min
    total_count = scope.count

    records = scope.limit(per_page).offset((page - 1) * per_page)
    meta = {
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: (total_count.to_f / per_page).ceil
    }
    [ records, meta ]
  end

  def positive_integer(value)
    number = Integer(value.to_s, 10, exception: false)
    number if number&.positive?
  end
end

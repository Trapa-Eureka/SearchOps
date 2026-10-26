class SearchResult < ApplicationRecord
  URL_MAX_LENGTH = 2048
  TITLE_MAX_LENGTH = 500
  SNIPPET_MAX_LENGTH = 2000
  EXTRA_MAX_BYTES = 4096

  belongs_to :search_run

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :position, uniqueness: { scope: :search_run_id }
  validates :url, presence: true, length: { maximum: URL_MAX_LENGTH }
  validates :title, length: { maximum: TITLE_MAX_LENGTH }, allow_nil: true
  validates :snippet, length: { maximum: SNIPPET_MAX_LENGTH }, allow_nil: true
  validates :display_domain, length: { maximum: 255 }, allow_nil: true
  validate :url_is_http
  validate :extra_is_bounded

  private

  def url_is_http
    return if url.blank?

    uri = URI.parse(url)
    errors.add(:url, "must be an http(s) URL") unless uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    errors.add(:url, "is not a valid URL")
  end

  def extra_is_bounded
    return if extra.to_json.bytesize <= EXTRA_MAX_BYTES

    errors.add(:extra, "is too large (max #{EXTRA_MAX_BYTES} bytes)")
  end
end

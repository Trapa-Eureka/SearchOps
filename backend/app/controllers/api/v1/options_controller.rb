module Api
  module V1
    # The allowed values for the keyword form and the limits that apply, so a client never has to
    # copy them. Values come straight from the models that enforce them.
    class OptionsController < BaseController
      def show
        render json: {
          data: {
            engines: Keyword::ENGINES,
            countries: Keyword::COUNTRIES,
            languages: Keyword::LANGUAGES,
            schedules: Keyword::SCHEDULES,
            limits: {
              query_max_length: Keyword::QUERY_MAX_LENGTH,
              location_max_length: Keyword::LOCATION_MAX_LENGTH,
              max_keywords: Keyword.max_keywords,
              intent_text_max_length: IntentRequest::TEXT_MAX_LENGTH,
              max_per_page: Paginatable::MAX_PER_PAGE
            },
            features: { intent_planning: Intent::Config.enabled? }
          }
        }
      end
    end
  end
end

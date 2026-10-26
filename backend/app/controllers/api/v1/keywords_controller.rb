module Api
  module V1
    class KeywordsController < BaseController
      before_action :set_keyword, only: %i[show update destroy]

      def index
        scope = Keyword.order(created_at: :desc, id: :desc)
        scope = scope.where(active: ActiveModel::Type::Boolean.new.cast(params[:active])) if params[:active].present?

        keywords, meta = paginate(scope)
        keywords = keywords.to_a
        freshness = KeywordFreshness.for(keywords)
        activity = KeywordActivity.for(keywords)
        render json: { data: keywords.map { |keyword| KeywordSerializer.call(keyword, freshness[keyword.id], activity[keyword.id]) }, meta: meta }
      end

      def show
        render json: { data: serialize(@keyword) }
      end

      def create
        keyword = Keyword.new(keyword_params)

        if keyword.save
          render json: { data: serialize(keyword) }, status: :created,
                 location: api_v1_keyword_path(keyword)
        else
          render_validation_errors(keyword)
        end
      end

      def update
        if @keyword.update(keyword_params)
          render json: { data: serialize(@keyword) }
        else
          render_validation_errors(@keyword)
        end
      end

      def destroy
        @keyword.destroy!
        head :no_content
      end

      private

      def serialize(keyword)
        KeywordSerializer.call(keyword, KeywordFreshness.for(keyword)[keyword.id], KeywordActivity.for(keyword)[keyword.id])
      end

      def set_keyword
        @keyword = Keyword.find(params[:id])
      end

      def keyword_params
        params.expect(keyword: %i[query engine country language location target_domain active schedule])
      end
    end
  end
end

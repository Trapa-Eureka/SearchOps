Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  get "health" => "health#show"

  namespace :api do
    namespace :v1 do
      get "metrics/summary", to: "metrics#summary"
      get "options", to: "options#show"
      get "searches", to: "runs#index"

      post "intent/plan", to: "intents#plan"
      get "intent/plan/:id", to: "intents#show"
      post "intent/plan/:id/confirm", to: "intents#confirm"

      resources :keywords, only: %i[index show create update destroy] do
        resources :searches, only: %i[index show create]
        resource :rank_history, only: :show, controller: "rank_histories"
      end
    end
  end

  # Defines the root path route ("/")
  # root "posts#index"
end

Rails.application.routes.draw do
  root "dashboard#index"

  get "browse", to: "browse#show"
  get "search", to: "search#index"

  resources :categories, only: %i[index show update destroy]

  resources :entries, only: [] do
    resources :tags, only: %i[create destroy]
  end

  get "up", to: "rails/health#show", as: :rails_health_check
end

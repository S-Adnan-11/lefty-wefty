Rails.application.routes.draw do
  root "workspace#show"
  get "signup", to: "signups#new"
  post "signup", to: "signups#create"
  resource :session, only: %i[new create destroy]
  resources :passwords, param: :token, only: %i[new create edit update]
  resources :products, only: %i[index show new create edit update] do
    post :archive, on: :member
    resources :stock_movements, only: :create
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end

Rails.application.routes.draw do
  root "workspace#show"
  get "robots.txt", to: "public_pages#robots", defaults: { format: :text }
  get "sitemap.xml", to: "public_pages#sitemap", defaults: { format: :xml }
  resource :account, only: %i[show update]
  resource :business_settings, only: %i[edit update], controller: "business_settings" do
    get :logo
  end
  resource :report, only: :show
  resources :stock_movements, only: :index
  get "signup", to: "signups#new"
  post "signup", to: "signups#create"
  resource :session, only: %i[new create destroy]
  resources :passwords, param: :token, only: %i[new create edit update]
  resources :orders do
    post :confirm, on: :member
    post :void, on: :member
  end
  resources :products, only: %i[index show new create edit update] do
    post :archive, on: :member
    resources :stock_movements, only: :create
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end

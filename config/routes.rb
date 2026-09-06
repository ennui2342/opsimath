Rails.application.routes.draw do
  root "pending_decisions#index"
  resource :session
  resources :passwords, param: :token

  resources :works, only: [ :index, :show ]

  # The offline shop-lookup PWA (docs/MOBILE.md) — bearer-token, no session.
  namespace :mobile do
    get "/", to: "app#show", as: :app
    get "manifest.webmanifest", to: "app#manifest", as: :manifest
    get "service-worker.js", to: "app#service_worker", as: :service_worker
    get "snapshot", to: "snapshots#show"
    get "snapshot/version", to: "snapshots#version"
  end
  resources :pending_decisions, only: [ :index, :show ] do
    member do
      post :accept
      post :reject
      post :resolve # edition_reconciliation kind only — see PendingDecisionsController#resolve
    end
  end
  resources :editions, only: [] do
    resource :metadata, only: [ :show, :update ], controller: "edition_metadata"
  end

  # Settings — authority control is the first section (docs/AUTHORITY_CONTROL.md).
  namespace :settings do
    get "/", to: redirect("/settings/authorities")
    get "authorities", to: "authorities#index"
    get "authorities/:vocabulary", to: "authorities#show", as: :authority
    post "authorities/:vocabulary/rescan", to: "authorities#rescan", as: :authority_rescan
    post "authorities/:vocabulary/terms", to: "authority_terms#create", as: :authority_terms
    patch "authorities/:vocabulary/terms/:id", to: "authority_terms#update", as: :authority_term
    delete "authorities/:vocabulary/terms/:id", to: "authority_terms#destroy"
    post "authorities/:vocabulary/variants", to: "authority_variants#create", as: :authority_variants
    delete "authorities/:vocabulary/variants/:id", to: "authority_variants#destroy", as: :authority_variant
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end

Rails.application.routes.draw do
  root "pending_decisions#index"
  resource :session
  resources :passwords, param: :token

  # The book page is catalogue management (docs/CATALOG.md, build step 5):
  # the reading log, copies, and whether it's wanted.
  resources :works, only: [ :index, :show ] do
    resources :readings, only: [ :create, :update, :destroy ]
    # An edition's status / purchase details, or deleting a mistaken one.
    resources :editions, only: [ :destroy ] do
      patch :holding, on: :member
    end
    resource :want, only: [ :create, :destroy ]
    # "Not this edition" (docs/CATALOG.md, build step 7)
    resources :edition_changes, path: "editions", only: [ :edit, :update ]
  end

  # Bargain hunting (docs/BARGAIN_HUNTING.md): the wishlist, and per book
  # the cover picker + target price + current eBay listings.
  # Adding a book (docs/CATALOG.md, build step 6): find the work, choose
  # the edition, say what it is to you.
  get "add", to: "add_books#new", as: :add_book
  get "add/editions", to: "add_books#editions", as: :add_book_editions
  post "add", to: "add_books#create"

  # Who and what a book belongs to, linked from the book page.
  resources :authors, only: [ :show ]
  resources :series, only: [ :show ]
  get "publisher", to: "publishers#show", as: :publisher
  get "artist", to: "artists#show", as: :artist
  # Publishers' lines (ISFDB publication series), and collecting one.
  resources :lines, only: [ :show ] do
    member do
      post :collect
      delete :collect, action: :stop
      post :exclude
      post :include
    end
  end
  post "artist/want_cover", to: "artists#want_cover", as: :artist_want_cover

  resources :wishlist_items, path: "wishlist", only: [ :index, :show, :update ] do
    # One cover in or out of the chosen set, from a find card.
    post "covers/:cover_id/drop", action: :drop_cover, on: :member, as: :drop_cover
    post "covers/:cover_id/restore", action: :restore_cover, on: :member, as: :restore_cover
  end
  resources :finds, only: [ :index ]
  resources :ebay_listings, only: [ :edit, :update ] do
    post :dismiss, on: :member
    post :restore, on: :member
  end

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
    get "/", to: "authorities#index"
    # The collecting profile — what bargain hunting looks for (docs/BARGAIN_HUNTING.md).
    resource :collecting_profile, path: "collecting", only: [ :show, :update ]
    get "authorities", to: "authorities#index"
    get "authorities/:vocabulary", to: "authorities#show", as: :authority
    post "authorities/:vocabulary/rescan", to: "authorities#rescan", as: :authority_rescan
    get "authorities/:vocabulary/terms/preview", to: "authority_terms#preview", as: :authority_terms_preview
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

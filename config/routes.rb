Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token

  get "sign-up" => "registrations#new", as: :new_registration
  post "sign-up" => "registrations#create", as: :registration

  resources :books, only: %i[index new create show destroy] do
    member do
      get "read"
    end

    resources :bookmarks, only: :index
  end

  resources :bookmarks, only: %i[create destroy]

  # The word card: the shell loads instantly from precomputed grammar, then its
  # nested frame fetches the contextual translation.
  resources :tokens, only: :show do
    member do
      get "gloss"
    end
  end

  resources :words, only: %i[index show update destroy] do
    collection do
      post "add"
    end
  end

  resource :quiz, only: :show do
    get "card"
    post "answer"
  end

  get "up" => "rails/health#show", as: :rails_health_check

  root "books#index"
end

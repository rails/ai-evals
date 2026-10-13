Rails.application.routes.draw do
  match "/rails/conductor/action_mailbox(/*path)", to: "health#not_found", via: :all
  post "/rails/action_mailbox/relay/inbound_emails", to: "helpdesk_relay#create"

  scope "/api/v1" do
    post "account/create", to: "accounts#create", as: :account_create
    post "account/cancel", to: "accounts#cancel", as: :account_cancel
    post "account/reactivate", to: "accounts#reactivate", as: :account_reactivate
    get "portal", to: "accounts#portal"
    resource :account, only: :show

    post "sessions", to: "sessions#create"
    delete "session", to: "sessions#destroy"

    resource :me, controller: "profiles", only: %i[show update]
    put "me/password", to: "profiles#password"

    post "email_verifications", to: "email_verifications#create"
    post "email_verifications/confirm", to: "email_verifications#confirm"
    post "password_resets", to: "password_resets#create"
    post "password_resets/confirm", to: "password_resets#confirm"
    post "registrations", to: "registrations#create"

    resources :requests, only: %i[index show create update] do
      get :comments, on: :member
    end

    resources :tickets, only: %i[index show update] do
      get :comments, on: :member
      post :merge, on: :member
    end

    resources :invitations, only: %i[index show create destroy] do
      post :resend, on: :member
    end
    post "invitation_previews", to: "invitations#preview"
    post "invitation_acceptances", to: "invitations#accept"

    resources :users, only: %i[index show update]
    get "staff", to: "users#staff"

    resources :groups, only: %i[index show create update destroy]
    resources :group_memberships, only: %i[index show create destroy] do
      put :make_default, on: :member
    end
  end

  match "*path", to: "health#not_found", via: :all
end

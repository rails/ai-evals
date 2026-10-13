Rails.application.routes.draw do
  # Moderator area (HTTP Basic auth)
  namespace :moderate do
    root "quizzes#index"

    resource :import, only: %i[new create]

    resources :quizzes do
      resources :questions, only: %i[new create]
      resource :preview, only: %i[show create destroy]
      resource :export, only: :show
      resources :runs, only: %i[create]
    end

    resources :questions, only: %i[edit update destroy] do
      patch :move, on: :member
    end

    resources :runs, only: %i[show destroy] do
      member do
        post :start
        post :close_question
        post :advance
        post :pick_winners
        delete :winners, action: :reset_winners
      end

      # Responses of a finished game (like Google Forms): a summary, per question, and per player
      scope module: :runs do
        resources :responses, only: :index
        resources :question_responses, path: "responses/questions", only: :show
        resources :participant_responses, path: "responses/participants", only: :show
      end
    end
  end

  # Players
  get "r/:code" => "plays#show", :as => :play
  resource :participation, path: "r/:code/participation", only: %i[create]
  resources :answers, path: "r/:code/answers", only: %i[create]

  get "up" => "rails/health#show", :as => :rails_health_check

  root "home#show"
end

# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_28_084415) do
  create_table "answers", force: :cascade do |t|
    t.integer "participation_id", null: false
    t.integer "question_id", null: false
    t.integer "option_index", null: false
    t.boolean "correct", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "elapsed_ms", default: 0, null: false
    t.index ["participation_id", "question_id"], name: "index_answers_on_participation_id_and_question_id", unique: true
    t.index ["question_id"], name: "index_answers_on_question_id"
  end

  create_table "participations", force: :cascade do |t|
    t.integer "run_id", null: false
    t.string "uid", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "score", default: 0, null: false
    t.integer "correct_time_ms", default: 0, null: false
    t.boolean "winner", default: false, null: false
    t.index ["run_id", "uid"], name: "index_participations_on_run_id_and_uid", unique: true
    t.index ["run_id"], name: "index_participations_on_run_id"
  end

  create_table "questions", force: :cascade do |t|
    t.integer "quiz_id", null: false
    t.text "body", null: false
    t.json "options", default: [], null: false
    t.integer "position", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["quiz_id", "position"], name: "index_questions_on_quiz_id_and_position"
    t.index ["quiz_id"], name: "index_questions_on_quiz_id"
  end

  create_table "quizzes", force: :cascade do |t|
    t.string "title", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "winners_count", default: 3, null: false
    t.integer "timer_minutes", default: 0, null: false
    t.integer "timer_seconds", default: 0, null: false
  end

  create_table "runs", force: :cascade do |t|
    t.integer "quiz_id", null: false
    t.string "code", null: false
    t.string "state", default: "idle", null: false
    t.integer "current_question_id"
    t.string "question_state"
    t.datetime "question_started_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_runs_on_code", unique: true
    t.index ["current_question_id"], name: "index_runs_on_current_question_id"
    t.index ["quiz_id"], name: "index_runs_on_quiz_id"
  end

  add_foreign_key "answers", "participations"
  add_foreign_key "answers", "questions"
  add_foreign_key "participations", "runs"
  add_foreign_key "questions", "quizzes"
  add_foreign_key "runs", "questions", column: "current_question_id", on_delete: :nullify
  add_foreign_key "runs", "quizzes"
end

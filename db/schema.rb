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

ActiveRecord::Schema[8.0].define(version: 2026_08_23_010000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "blocks", force: :cascade do |t|
    t.bigint "book_id", null: false
    t.bigint "book_image_id"
    t.integer "position", null: false
    t.string "kind", default: "paragraph", null: false
    t.integer "page_number"
    t.text "text"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "words", default: [], null: false
    t.index ["book_id", "position"], name: "index_blocks_on_book_id_and_position", unique: true
    t.index ["book_id"], name: "index_blocks_on_book_id"
    t.index ["book_image_id"], name: "index_blocks_on_book_image_id"
  end

  create_table "book_images", force: :cascade do |t|
    t.bigint "book_id", null: false
    t.string "checksum", null: false
    t.integer "width"
    t.integer "height"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["book_id", "checksum"], name: "index_book_images_on_book_id_and_checksum", unique: true
    t.index ["book_id"], name: "index_book_images_on_book_id"
  end

  create_table "bookmarks", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "book_id", null: false
    t.bigint "token_id", null: false
    t.integer "block_position", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["book_id"], name: "index_bookmarks_on_book_id"
    t.index ["token_id"], name: "index_bookmarks_on_token_id"
    t.index ["user_id", "book_id", "block_position"], name: "index_bookmarks_on_user_id_and_book_id_and_block_position"
    t.index ["user_id", "token_id"], name: "index_bookmarks_on_user_id_and_token_id", unique: true
    t.index ["user_id"], name: "index_bookmarks_on_user_id"
  end

  create_table "books", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "title", null: false
    t.string "author"
    t.string "language", default: "es", null: false
    t.string "status", default: "pending", null: false
    t.string "source_filename"
    t.string "checksum"
    t.integer "page_count"
    t.integer "block_count", default: 0, null: false
    t.integer "word_count", default: 0, null: false
    t.text "ingest_error"
    t.datetime "ingested_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "checksum"], name: "index_books_on_user_id_and_checksum", unique: true, where: "(checksum IS NOT NULL)"
    t.index ["user_id", "status"], name: "index_books_on_user_id_and_status"
    t.index ["user_id"], name: "index_books_on_user_id"
  end

  create_table "glosses", force: :cascade do |t|
    t.bigint "lemma_id", null: false
    t.string "surface", null: false
    t.string "sentence_digest", null: false
    t.jsonb "payload", default: {}, null: false
    t.string "model"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lemma_id", "surface", "sentence_digest"], name: "index_glosses_on_lookup", unique: true
    t.index ["lemma_id"], name: "index_glosses_on_lemma_id"
  end

  create_table "lemmas", force: :cascade do |t|
    t.string "text", null: false
    t.string "pos", null: false
    t.string "language", default: "es", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["language", "text", "pos"], name: "index_lemmas_on_language_and_text_and_pos", unique: true
  end

  create_table "reading_progresses", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "book_id", null: false
    t.integer "block_position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["book_id"], name: "index_reading_progresses_on_book_id"
    t.index ["user_id", "book_id"], name: "index_reading_progresses_on_user_id_and_book_id", unique: true
    t.index ["user_id"], name: "index_reading_progresses_on_user_id"
  end

  create_table "reviews", force: :cascade do |t|
    t.bigint "vocab_entry_id", null: false
    t.bigint "sentence_id"
    t.integer "rating", null: false
    t.string "state_before"
    t.float "stability_after"
    t.float "difficulty_after"
    t.float "elapsed_days"
    t.float "scheduled_days"
    t.datetime "reviewed_at", null: false
    t.index ["sentence_id"], name: "index_reviews_on_sentence_id"
    t.index ["vocab_entry_id", "reviewed_at"], name: "index_reviews_on_vocab_entry_id_and_reviewed_at"
    t.index ["vocab_entry_id"], name: "index_reviews_on_vocab_entry_id"
  end

  create_table "sentences", force: :cascade do |t|
    t.bigint "book_id", null: false
    t.bigint "block_id", null: false
    t.integer "position", null: false
    t.integer "char_start", null: false
    t.integer "char_end", null: false
    t.text "text", null: false
    t.index ["block_id", "position"], name: "index_sentences_on_block_id_and_position", unique: true
    t.index ["block_id"], name: "index_sentences_on_block_id"
    t.index ["book_id"], name: "index_sentences_on_book_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "solid_queue_batch_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "batch_id", null: false
    t.datetime "created_at", null: false
    t.index ["batch_id"], name: "index_solid_queue_batch_executions_on_batch_id"
    t.index ["job_id"], name: "index_solid_queue_batch_executions_on_job_id", unique: true
  end

  create_table "solid_queue_batches", force: :cascade do |t|
    t.string "active_job_batch_id"
    t.string "description"
    t.text "on_finish"
    t.text "on_success"
    t.text "on_failure"
    t.text "metadata"
    t.integer "total_jobs", default: 0, null: false
    t.integer "completed_jobs", default: 0, null: false
    t.integer "failed_jobs", default: 0, null: false
    t.datetime "enqueued_at"
    t.datetime "finished_at"
    t.datetime "failed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_batch_id"], name: "index_solid_queue_batches_on_active_job_batch_id", unique: true
    t.index ["finished_at"], name: "index_solid_queue_batches_on_finished_at"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.bigint "batch_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["batch_id"], name: "index_solid_queue_jobs_on_batch_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "tokens", force: :cascade do |t|
    t.bigint "book_id", null: false
    t.bigint "block_id", null: false
    t.bigint "sentence_id", null: false
    t.bigint "lemma_id"
    t.integer "position", null: false
    t.integer "char_start", null: false
    t.integer "char_end", null: false
    t.string "surface", null: false
    t.string "pos"
    t.jsonb "morph", default: {}, null: false
    t.index ["block_id", "position"], name: "index_tokens_on_block_id_and_position"
    t.index ["lemma_id", "book_id"], name: "index_tokens_on_lemma_id_and_book_id"
    t.index ["sentence_id"], name: "index_tokens_on_sentence_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  create_table "vocab_entries", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "lemma_id", null: false
    t.bigint "source_book_id"
    t.bigint "source_token_id"
    t.string "status", default: "learning", null: false
    t.text "gloss"
    t.text "note"
    t.string "fsrs_state", default: "new", null: false
    t.float "stability"
    t.float "difficulty"
    t.datetime "due_at"
    t.datetime "last_reviewed_at"
    t.integer "reps", default: 0, null: false
    t.integer "lapses", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "learning_steps", default: 0, null: false
    t.float "scheduled_days", default: 0.0, null: false
    t.index ["lemma_id"], name: "index_vocab_entries_on_lemma_id"
    t.index ["source_book_id"], name: "index_vocab_entries_on_source_book_id"
    t.index ["source_token_id"], name: "index_vocab_entries_on_source_token_id"
    t.index ["user_id", "due_at"], name: "index_vocab_entries_on_user_id_and_due_at"
    t.index ["user_id", "lemma_id"], name: "index_vocab_entries_on_user_id_and_lemma_id", unique: true
    t.index ["user_id", "status"], name: "index_vocab_entries_on_user_id_and_status"
    t.index ["user_id"], name: "index_vocab_entries_on_user_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "blocks", "book_images"
  add_foreign_key "blocks", "books"
  add_foreign_key "book_images", "books"
  add_foreign_key "bookmarks", "books"
  add_foreign_key "bookmarks", "tokens", on_delete: :cascade
  add_foreign_key "bookmarks", "users"
  add_foreign_key "books", "users"
  add_foreign_key "glosses", "lemmas"
  add_foreign_key "reading_progresses", "books"
  add_foreign_key "reading_progresses", "users"
  add_foreign_key "reviews", "sentences", on_delete: :nullify
  add_foreign_key "reviews", "vocab_entries"
  add_foreign_key "sentences", "blocks"
  add_foreign_key "sentences", "books"
  add_foreign_key "sessions", "users"
  add_foreign_key "solid_queue_batch_executions", "solid_queue_batches", column: "batch_id", on_delete: :cascade
  add_foreign_key "solid_queue_batch_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "tokens", "blocks"
  add_foreign_key "tokens", "books"
  add_foreign_key "tokens", "lemmas"
  add_foreign_key "tokens", "sentences"
  add_foreign_key "vocab_entries", "books", column: "source_book_id", on_delete: :nullify
  add_foreign_key "vocab_entries", "lemmas"
  add_foreign_key "vocab_entries", "tokens", column: "source_token_id", on_delete: :nullify
  add_foreign_key "vocab_entries", "users"
end

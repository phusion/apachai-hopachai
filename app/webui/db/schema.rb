# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20140217105429) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_admin_comments", force: true do |t|
    t.string   "namespace"
    t.text     "body"
    t.string   "resource_id",   null: false
    t.string   "resource_type", null: false
    t.integer  "author_id"
    t.string   "author_type"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["author_type", "author_id"], :name => "index_active_admin_comments_on_author_type_and_author_id"
    t.index ["namespace"], :name => "index_active_admin_comments_on_namespace"
    t.index ["resource_type", "resource_id"], :name => "index_active_admin_comments_on_resource_type_and_resource_id"
  end

  create_table "admin_users", force: true do |t|
    t.string   "email",                  default: "", null: false
    t.string   "encrypted_password",     default: "", null: false
    t.string   "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer  "sign_in_count",          default: 0,  null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string   "current_sign_in_ip"
    t.string   "last_sign_in_ip"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["email"], :name => "index_admin_users_on_email", :unique => true
    t.index ["reset_password_token"], :name => "index_admin_users_on_reset_password_token", :unique => true
  end

  create_table "users", force: true do |t|
    t.string   "email",                  default: "", null: false
    t.string   "encrypted_password",     default: "", null: false
    t.string   "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer  "sign_in_count",          default: 0,  null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string   "current_sign_in_ip"
    t.string   "last_sign_in_ip"
    t.string   "name",                                null: false
    t.datetime "created_at",                          null: false
    t.datetime "updated_at",                          null: false
    t.index ["email"], :name => "index_users_on_email", :unique => true
    t.index ["reset_password_token"], :name => "index_users_on_reset_password_token", :unique => true
  end

  create_table "projects", force: true do |t|
    t.integer  "owner_id",    null: false
    t.string   "name",        null: false
    t.string   "repo_url",    null: false
    t.datetime "created_at",  null: false
    t.datetime "updated_at",  null: false
    t.text     "public_key",  null: false
    t.text     "private_key", null: false
    t.index ["owner_id"], :name => "fk__projects_owner_id"
    t.foreign_key ["owner_id"], "users", ["id"], :on_update => :cascade, :on_delete => :no_action, :name => "fk_projects_owner_id"
  end

  create_table "job_sets", force: true do |t|
    t.integer  "project_id",                           null: false
    t.string   "state_cd",                             null: false
    t.datetime "created_at",                           null: false
    t.string   "revision",                             null: false
    t.string   "before_revision",                      null: false
    t.string   "branch"
    t.string   "tag"
    t.string   "author_name",                          null: false
    t.string   "author_email",                         null: false
    t.string   "subject",                              null: false
    t.string   "language"
    t.text     "bundler_args"
    t.boolean  "init_git_submodules",   default: true, null: false
    t.text     "before_install_script"
    t.text     "install_script"
    t.text     "before_script"
    t.text     "script"
    t.text     "after_success_script"
    t.text     "after_failure_script"
    t.text     "after_script"
    t.index ["project_id"], :name => "fk__job_sets_project_id"
    t.foreign_key ["project_id"], "projects", ["id"], :on_update => :cascade, :on_delete => :cascade, :name => "fk_job_sets_project_id"
  end

  create_table "jobs", force: true do |t|
    t.integer  "job_set_id",    null: false
    t.string   "state_cd",      null: false
    t.integer  "number",        null: false
    t.string   "name",          null: false
    t.string   "log_file_path", null: false
    t.integer  "lock_version"
    t.datetime "created_at",    null: false
    t.text     "environment"
    t.datetime "start_time"
    t.datetime "end_time"
    t.index ["job_set_id"], :name => "fk__jobs_job_set_id"
    t.foreign_key ["job_set_id"], "job_sets", ["id"], :on_update => :cascade, :on_delete => :cascade, :name => "fk_jobs_job_set_id"
  end

end

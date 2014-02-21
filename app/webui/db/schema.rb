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

  create_table "users", force: true do |t|
    t.string   "username",                               null: false
    t.string   "email",                  default: "",    null: false
    t.string   "encrypted_password",     default: "",    null: false
    t.string   "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer  "sign_in_count",          default: 0,     null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string   "current_sign_in_ip"
    t.string   "last_sign_in_ip"
    t.boolean  "admin",                  default: false, null: false
    t.datetime "created_at",                             null: false
    t.datetime "updated_at",                             null: false
    t.index ["email"], :name => "index_users_on_email", :unique => true
    t.index ["reset_password_token"], :name => "index_users_on_reset_password_token", :unique => true
    t.index ["username"], :name => "index_users_on_username", :unique => true
  end

  create_table "projects", force: true do |t|
    t.integer  "owner_id",        null: false
    t.string   "name",            null: false
    t.string   "repo_url",        null: false
    t.datetime "created_at",      null: false
    t.datetime "updated_at",      null: false
    t.string   "webhook_key",     null: false
    t.text     "public_key",      null: false
    t.text     "private_key",     null: false
    t.text     "public_ssh_key",  null: false
    t.text     "private_ssh_key", null: false
    t.index ["owner_id"], :name => "fk__projects_owner_id"
    t.foreign_key ["owner_id"], "users", ["id"], :on_update => :cascade, :on_delete => :no_action, :name => "fk_projects_owner_id"
  end

  create_table "authorizations", force: true do |t|
    t.integer "user_id",                    null: false
    t.integer "project_id",                 null: false
    t.boolean "admin",      default: false, null: false
    t.index ["project_id"], :name => "fk__authorizations_project_id"
    t.index ["user_id"], :name => "fk__authorizations_user_id"
    t.foreign_key ["project_id"], "projects", ["id"], :on_update => :cascade, :on_delete => :cascade, :name => "fk_authorizations_project_id"
    t.foreign_key ["user_id"], "users", ["id"], :on_update => :cascade, :on_delete => :cascade, :name => "fk_authorizations_user_id"
  end

  create_table "builds", force: true do |t|
    t.integer  "project_id",                            null: false
    t.string   "state_cd",                              null: false
    t.integer  "number",                                null: false
    t.datetime "created_at",                            null: false
    t.datetime "finalized_at"
    t.string   "revision",                              null: false
    t.string   "before_revision"
    t.string   "branch"
    t.string   "tag"
    t.string   "author_name",                           null: false
    t.string   "author_email",                          null: false
    t.string   "committer_name",                        null: false
    t.string   "committer_email",                       null: false
    t.string   "subject",                               null: false
    t.string   "language"
    t.text     "bundler_args"
    t.boolean  "init_git_submodules",   default: true,  null: false
    t.boolean  "fast_finish",           default: false, null: false
    t.text     "notifications",                         null: false
    t.text     "before_install_script",                 null: false
    t.text     "install_script",                        null: false
    t.text     "before_script",                         null: false
    t.text     "script",                                null: false
    t.text     "after_success_script",                  null: false
    t.text     "after_failure_script",                  null: false
    t.text     "after_script",                          null: false
    t.index ["project_id"], :name => "fk__builds_project_id"
    t.foreign_key ["project_id"], "projects", ["id"], :on_update => :cascade, :on_delete => :cascade, :name => "fk_builds_project_id"
  end

  create_table "jobs", force: true do |t|
    t.integer  "build_id",                       null: false
    t.string   "state_cd",                       null: false
    t.integer  "number",                         null: false
    t.string   "name",                           null: false
    t.string   "log_file_name",                  null: false
    t.integer  "worker_pid"
    t.integer  "lock_version"
    t.datetime "created_at",                     null: false
    t.text     "environment",                    null: false
    t.boolean  "allow_failures", default: false, null: false
    t.datetime "start_time"
    t.datetime "end_time"
    t.index ["build_id"], :name => "fk__jobs_build_id"
    t.index ["state_cd"], :name => "jobs_processing", :conditions => "((state_cd)::text = 'processing'::text)"
    t.foreign_key ["build_id"], "builds", ["id"], :on_update => :cascade, :on_delete => :cascade, :name => "fk_jobs_build_id"
  end

end

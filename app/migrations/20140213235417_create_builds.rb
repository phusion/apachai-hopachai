class CreateBuilds < ActiveRecord::Migration
  def change
    create_table(:builds) do |t|
      t.integer :project_id, :null => false, :foreign_key => {
        :on_delete => :cascade,
        :on_update => :cascade
      }

      t.string :state_cd, :null => false
      t.integer :number, :null => false
      t.timestamp :created_at, :null => false
      t.timestamp :finalized_at

      t.string :revision, :null => false
      t.string :before_revision
      t.string :branch
      t.string :tag
      t.string :author_name, :null => false
      t.string :author_email, :null => false
      t.string :committer_name, :null => false
      t.string :committer_email, :null => false
      t.string :subject, :null => false

      t.string :language
      t.text :bundler_args
      t.boolean :init_git_submodules, :null => false, :default => true
      t.boolean :fast_finish, :null => false, :default => false
      t.text :notifications, :null => false

      t.text :before_install_script, :null => false
      t.text :install_script, :null => false
      t.text :before_script, :null => false
      t.text :script, :null => false
      t.text :after_success_script, :null => false
      t.text :after_failure_script, :null => false
      t.text :after_script, :null => false
    end
  end
end

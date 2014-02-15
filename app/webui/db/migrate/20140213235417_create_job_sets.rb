class CreateJobSets < ActiveRecord::Migration
  def change
    create_table(:job_sets) do |t|
      t.integer :project_id, :null => false, :foreign_key => {
        :on_delete => :cascade,
        :on_update => :cascade
      }

      t.string :state_cd, :null => false
      t.timestamp :created_at, :null => false

      t.string :revision, :null => false
      t.string :before_revision, :null => false
      t.string :branch
      t.string :tag
      t.string :author_name, :null => false
      t.string :author_email, :null => false
      t.string :subject, :null => false

      t.string :language
      t.text :bundler_args
      t.boolean :init_git_submodules, :null => false, :default => true

      t.text :before_install_script
      t.text :install_script
      t.text :before_script
      t.text :script
      t.text :after_success_script
      t.text :after_failure_script
      t.text :after_script
    end
  end
end

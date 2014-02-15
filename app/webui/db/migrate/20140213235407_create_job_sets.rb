class CreateJobSet < ActiveRecord::Migration
  def change
    create_table(:job_sets) do |t|
      t.integer :project_id, :null => false, :foreign_key => {
        :on_delete => :cascade,
        :on_update => :cascade
      }
      t.string :state, :null => false
      t.string :revision, :null => false
      t.string :author_name, :null => false
      t.string :author_email, :null => false
      t.string :subject, :null => false
      t.string :before_revision, :null => false
      t.timestamp :created_at, :null => false
    end
  end
end

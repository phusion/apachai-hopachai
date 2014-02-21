class CreateJobs < ActiveRecord::Migration
  def up
    create_table(:jobs) do |t|
      t.integer :build_id, :null => false, :foreign_key => {
        :on_delete => :cascade,
        :on_update => :cascade
      }
      t.string  :state_cd, :null => false
      t.integer :number, :null => false
      t.string  :name, :null => false
      t.string  :log_file_name, :null => false
      t.integer :worker_pid
      t.integer :lock_version
      t.timestamp :created_at, :null => false

      t.text :environment, :null => false
      t.boolean :allow_failures, :null => false, :default => false

      t.timestamp :start_time
      t.timestamp :end_time

      t.index :state_cd, :name => "jobs_processing", :conditions => "state_cd = 'processing'"
    end
  end

  def down
    drop_table :jobs
  end
end

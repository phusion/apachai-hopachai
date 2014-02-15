class CreateJob < ActiveRecord::Migration
  def change
    create_table(:jobs) do |t|
      t.integer :job_set_id, :null => false, :foreign_key => {
        :on_delete => :cascade,
        :on_update => :cascade
      }
      t.string  :state_cd, :null => false
      t.integer :number, :null => false
      t.string  :name, :null => false
      t.string  :log_file_path, :null => false
      t.integer :lock_version
      t.timestamp :created_at, :null => false

      t.text :environment

      t.timestamp :start_time
      t.timestamp :end_time
    end
  end
end

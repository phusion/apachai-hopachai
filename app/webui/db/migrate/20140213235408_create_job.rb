class CreateJob < ActiveRecord::Migration
  def change
    create_table(:jobs) do |t|
      t.integer :job_set_id, :null => false, :foreign_key => {
        :on_delete => :cascade,
        :on_update => :cascade
      }
      t.string :state, :null => false
      t.string :name, :null => false
      t.timestamp :created_at, :null => false
    end
  end
end

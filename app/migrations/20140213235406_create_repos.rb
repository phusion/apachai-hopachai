class CreateRepos < ActiveRecord::Migration
  def change
    create_table(:repos) do |t|
      t.integer :owner_id, :null => false, :foreign_key => {
        :references => :users,
        :on_delete => :no_action,
        :on_update => :cascade
      }
      t.string :name, :null => false
      t.string :url, :null => false
      t.timestamps :null => false
      t.string :webhook_key, :null => false
      t.text :public_key, :null => false
      t.text :private_key, :null => false
      t.text :public_ssh_key, :null => false
      t.text :private_ssh_key, :null => false
    end
  end
end

class CreateAuthorizations < ActiveRecord::Migration
  def change
    create_table(:authorizations) do |t|
      t.integer :user_id, :null => false, :foreign_key => {
        :on_delete => :cascade,
        :on_update => :cascade
      }
      t.integer :repo_id, :null => false, :foreign_key => {
        :on_delete => :cascade,
        :on_update => :cascade
      }
      t.boolean :admin, :null => false, :default => false
    end
  end
end

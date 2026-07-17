class CreateSidebarMenuSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :sidebar_menu_settings do |t|
      t.string :menu_key, null: false
      t.boolean :active, default: true, null: false
      t.timestamps
    end

    add_index :sidebar_menu_settings, :menu_key, unique: true
  end
end

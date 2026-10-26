class CreateSearchResults < ActiveRecord::Migration[8.1]
  def change
    create_table :search_results do |t|
      t.references :search_run, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :title
      t.text :url, null: false
      t.string :display_domain
      t.text :snippet
      t.jsonb :extra, null: false, default: {}

      t.timestamps
    end

    add_index :search_results, %i[search_run_id position], unique: true
    add_check_constraint :search_results, "position >= 1", name: "search_results_position_positive"
  end
end

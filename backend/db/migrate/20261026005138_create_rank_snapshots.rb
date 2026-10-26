class CreateRankSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :rank_snapshots do |t|
      t.references :keyword, null: false, foreign_key: true
      t.references :search_run, null: false, foreign_key: true, index: { unique: true }
      t.string :target_domain, null: false
      # NULL means "not found in the retrieved window". It is never stored as 0.
      t.integer :rank
      t.datetime :captured_at, null: false

      t.timestamps
    end

    add_index :rank_snapshots, %i[keyword_id captured_at]
    add_check_constraint :rank_snapshots, "rank IS NULL OR rank >= 1", name: "rank_snapshots_rank_positive"
  end
end

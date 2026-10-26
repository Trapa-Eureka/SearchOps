class CreateKeywords < ActiveRecord::Migration[8.1]
  def change
    create_table :keywords do |t|
      t.string :query, null: false
      t.string :engine, null: false, default: "google"
      t.string :country, null: false
      t.string :language, null: false
      t.string :location
      t.string :target_domain
      t.boolean :active, null: false, default: true
      t.string :schedule, null: false, default: "manual"

      t.timestamps
    end

    # One keyword per identical search setting. NULLs compare equal so that two
    # keywords without a location (or target domain) are still duplicates.
    add_index :keywords,
              %i[query engine country language location target_domain],
              unique: true,
              nulls_not_distinct: true,
              name: "index_keywords_on_search_settings"
    add_index :keywords, %i[active schedule]
  end
end

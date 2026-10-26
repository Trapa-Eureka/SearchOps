class CreateIntentRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :intent_requests do |t|
      # Subject to a retention policy (decided in Stage 5).
      t.text :original_text, null: false
      t.string :classifier_version
      t.jsonb :plan
      t.string :outcome, null: false
      t.integer :duration_ms
      t.string :fallback_reason

      t.timestamps
    end

    add_index :intent_requests, :created_at
  end
end

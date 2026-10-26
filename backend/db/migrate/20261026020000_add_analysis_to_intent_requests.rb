class AddAnalysisToIntentRequests < ActiveRecord::Migration[8.1]
  def change
    change_table :intent_requests, bulk: true do |t|
      # How the plan was reached: classifier scores, where each field came from, what is missing.
      t.jsonb :analysis, null: false, default: {}
      t.datetime :confirmed_at
      # What confirming did (keyword and run ids), so confirming twice cannot search twice.
      t.jsonb :execution
    end
  end
end

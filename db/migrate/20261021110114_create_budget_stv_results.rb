class CreateBudgetStvResults < ActiveRecord::Migration[8.0]
  def change
    create_table :budget_stv_results do |t|
      t.references :budget, null: false, foreign_key: true
      t.references :heading, null: false, foreign_key: { to_table: :budget_headings }

      t.datetime :calculated_at, null: false
      t.bigint :calculated_by_user_id, null: true
      t.string :calculator_version, null: false
      t.string :election_seed, null: false

      t.integer :seats, null: false
      t.integer :quota, null: false
      t.integer :votes_cast, null: false
      t.boolean :dynamic_quota_enabled, null: false, default: false

      t.jsonb :winners, null: false, default: []
      t.jsonb :elimination_log, null: false, default: []
      t.jsonb :rounds, null: false, default: []
      t.jsonb :investment_titles, null: false, default: {}

      t.decimal :exhausted_total, precision: 15, scale: 6, null: false, default: 0.0
      t.integer :unfilled_seats, null: false, default: 0

      t.timestamps
    end

    add_index :budget_stv_results, [:heading_id, :calculated_at],
              order: { calculated_at: :desc },
              name: "index_budget_stv_results_on_heading_and_time"

    add_foreign_key :budget_stv_results, :users,
                    column: :calculated_by_user_id, on_delete: :nullify
  end
end

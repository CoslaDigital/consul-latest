class AddRunOptionsToSensemakerJobs < ActiveRecord::Migration[8.0]
  def change
    add_column :sensemaker_jobs, :run_options, :jsonb, null: false, default: {}
  end
end

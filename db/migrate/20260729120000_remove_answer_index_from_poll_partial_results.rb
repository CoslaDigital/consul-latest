class RemoveAnswerIndexFromPollPartialResults < ActiveRecord::Migration[7.2]
  def up
    execute "DROP INDEX IF EXISTS index_poll_partial_results_on_answer"
  end

  def down
    add_index :poll_partial_results, :answer, name: "index_poll_partial_results_on_answer"
  end
end

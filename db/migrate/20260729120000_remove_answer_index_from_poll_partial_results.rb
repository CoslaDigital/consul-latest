class RemoveAnswerIndexFromPollPartialResults < ActiveRecord::Migration[7.2]
  def up
    remove_index :poll_partial_results, name: "index_poll_partial_results_on_answer", if_exists: true
  end

  def down
    add_index :poll_partial_results, :answer, name: "index_poll_partial_results_on_answer"
  end
end

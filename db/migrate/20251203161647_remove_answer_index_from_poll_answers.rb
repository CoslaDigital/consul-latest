class RemoveAnswerIndexFromPollAnswers < ActiveRecord::Migration[7.2]
  def up
    execute "DROP INDEX IF EXISTS index_poll_answers_on_question_id_and_answer"
  end

  def down
    add_index :poll_answers, [:question_id, :answer], name: "index_poll_answers_on_question_id_and_answer"
  end
end

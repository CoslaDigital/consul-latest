class RemoveAnswerIndexFromPollAnswers < ActiveRecord::Migration[7.2]
  def up
    remove_index :poll_answers, name: "index_poll_answers_on_question_id_and_answer", if_exists: true
  end

  def down
    add_index :poll_answers, [:question_id, :answer], name: "index_poll_answers_on_question_id_and_answer"
  end
end

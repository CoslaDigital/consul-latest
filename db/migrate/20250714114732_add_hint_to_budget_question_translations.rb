class AddHintToBudgetQuestionTranslations < ActiveRecord::Migration[7.0]
  def change
    add_column :budget_question_translations, :hint, :text
  end
end

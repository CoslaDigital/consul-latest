class Admin::Settings::ModerationTabComponent < ApplicationComponent
  def tab
    "#tab-moderation"
  end
  
  def settings
    %w[
      moderation.openai
#      moderation.google
#      moderation.llama
      ]
  end
end
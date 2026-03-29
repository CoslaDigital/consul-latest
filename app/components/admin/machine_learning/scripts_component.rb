class Admin::MachineLearning::ScriptsComponent < ApplicationComponent
  attr_reader :machine_learning_job

  def initialize(machine_learning_job)
    @machine_learning_job = machine_learning_job
  end

  private

  def script_select_options
    ::MachineLearning.script_select_options
  end

  def scripts_info
    ::MachineLearning.scripts_info
  end
end

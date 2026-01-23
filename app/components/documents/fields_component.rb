class Documents::FieldsComponent < ApplicationComponent
  attr_reader :f, :current_user
  delegate :can?, :current_user, to: :helpers

  def initialize(f)
    @f = f
  end

  def show_visibility_toggle?
    can?(:update, document) || (document.new_record? && can?(:create, Document))
  end

  private

    def document
      f.object
    end
end

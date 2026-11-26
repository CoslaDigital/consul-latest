class Admin::EventsController < Admin::BaseController
  include ImageAttributes
  include DocumentAttributes
  include MapLocationAttributes

  before_action :set_event, only: [:edit, :update, :destroy]
  before_action :destroy_map_location_association, only: :update

  # GET /admin/events
  # Shows a list (table) of manual events for easy management
  def index
    @events = Event.order(starts_at: :desc).page(params[:page])
  end

  def new
    @event = Event.new
  end

  def create
    @event = Event.new(event_params)
    if @event.save
      redirect_to admin_events_path, notice: "Event created successfully."
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @event.update(event_params)
      redirect_to admin_events_path, notice: "Event updated successfully."
    else
      render :edit
    end
  end

  def destroy
    @event.destroy
    redirect_to admin_events_path, notice: "Event deleted."
  end

  private

  def set_event
    @event = Event.find(params[:id])
  end

  def event_params
    params.require(:event).permit(allowed_params)
  end

  def allowed_params
    [
      :name,
      :description,
      :starts_at,
      :ends_at,
      :event_type,
      :location,
      image_attributes: image_attributes,
      documents_attributes: document_attributes,
      map_location_attributes: map_location_attributes
    ]
  end

  def destroy_map_location_association
    map_location_params = event_params[:map_location_attributes]

    if map_location_params.blank? || map_location_params.values.all?(&:blank?)
      @event.map_location = nil
    end
  end
end

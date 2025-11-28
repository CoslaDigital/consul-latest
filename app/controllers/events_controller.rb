# frozen_string_literal: true

class EventsController < ApplicationController
  skip_authorization_check
  before_action :set_event, only: %i[show edit update destroy]

  # GET /events (The Calendar)
  def index
    # Load everything for the view
    start_date = params.fetch(:start_date, Date.today).to_date
    range_start = start_date.beginning_of_month
    range_end = start_date.end_of_month
    @calendar_items = Event.all_in_range(range_start, range_end)

  end
  # GET /events/new (Only for manual events)
  # GET /events/new
  def new
    @event = Event.new
    # Optional: Default the start time to the current time or the parameter passed
    @event.starts_at = params[:start_date] ? Date.parse(params[:start_date]) : Time.current
  end

  # POST /events
  # POST /events
  def create
    @event = Event.new(event_params)

    if @event.save
      redirect_to events_path, notice: "Event was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /events/1
  # PATCH/PUT /events/1
  def update
    if @event.update(event_params)
      redirect_to events_path, notice: "Event was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /events/1
  def destroy
    @event.destroy
    redirect_to events_path, notice: "Event was successfully deleted."
  end

  private
  def set_event
    @event = Event.find(params[:id])
  end

  def event_params
    params.require(:event).permit(:name, :description, :starts_at, :ends_at)
  end
end

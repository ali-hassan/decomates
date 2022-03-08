class Admin2::ActiveSlotsController < ApplicationController
  # before_action :find_category, except: %i[index order change_category]

  def index
    @slots = AvailableSlot.where(active: true)
  end

  def new
    @category = AvailableSlot.new
    @shapes = @current_community.shapes
    @selected_shape_ids = @shapes.map { |s| s[:id] }
    render layout: false
  end
  def create
    @slot = AvailableSlot.create name: params[:name], day: params[:day], active: params[:available_slot][:active]
    redirect_to "/en/admin"
  end

  def show
  end
end

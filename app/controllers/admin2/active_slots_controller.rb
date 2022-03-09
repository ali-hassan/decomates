class Admin2::ActiveSlotsController < Admin2::AdminBaseController
  before_action :find_category, only: %i[edit update destroy]

  def index
    @slots = AvailableSlot.all
  end

  def new
    @category = AvailableSlot.new
    @shapes = @current_community.shapes
    @selected_shape_ids = @shapes.map { |s| s[:id] }
    render layout: false
  end

  def edit
    @shapes = @current_community.shapes
    @selected_shape_ids = CategoryListingShape.where(category_id: @category.id).map(&:listing_shape_id)
    render layout: false
  end

  def update
    @category.update!(category_params)
  rescue StandardError=> e
    flash[:error] = e.message
  ensure
    redirect_to admin2_listings_categories_path
  end

  def destroy
    @category.destroy
    redirect_to admin2_listings_categories_path
  end

  def create
    @slot = AvailableSlot.create name: params[:name], day: params[:day], active: (params[:available_slot].present? ? params[:available_slot][:active] : false)
    redirect_to "/en/admin"
  end

  def show
  end

  private
  def find_category
    @category = AvailableSlot.find_by_id(params[:id])
  end
end

class Admin2::ActiveSlotsController < ApplicationController
  before_action :find_category, except: %i[index new order change_category]
  def index
    @slots = AvailableSlot.where(active: true)
  end
end

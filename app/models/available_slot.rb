# == Schema Information
#
# Table name: available_slots
#
#  id         :bigint           not null, primary key
#  day        :datetime
#  name       :string(255)
#  active     :boolean
#  created_at :datetime         not null
#  updated_at :datetime         not null
#

class AvailableSlot < ApplicationRecord


  def new_record?
    id.nil?
  end
end

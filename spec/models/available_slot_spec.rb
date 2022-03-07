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

require 'rails_helper'

RSpec.describe AvailableSlot, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end

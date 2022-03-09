class AddFieldsToMessage < ActiveRecord::Migration[5.2]
  def change
    add_column :messages, :first_time_slot, :datetime
    add_column :messages, :second_time_slot, :datetime
    add_column :messages, :third_time_slot, :datetime
    add_column :messages, :receiver_phone, :string
    add_column :messages, :receiver_address, :text
    add_column :messages, :building_info, :text
  end
end

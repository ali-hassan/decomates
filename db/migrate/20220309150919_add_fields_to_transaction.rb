class AddFieldsToTransaction < ActiveRecord::Migration[5.2]
  def change
    add_column :transactions, :first_time_slot, :datetime
    add_column :transactions, :second_time_slot, :datetime
    add_column :transactions, :third_time_slot, :datetime
    add_column :transactions, :delivery_time_slot, :datetime
    add_column :transactions, :receiver_phone, :string
    add_column :transactions, :receiver_address, :text
    add_column :transactions, :building_info, :text
  end
end

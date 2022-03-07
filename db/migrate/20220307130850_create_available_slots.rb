class CreateAvailableSlots < ActiveRecord::Migration[5.2]
  def change
    create_table :available_slots do |t|
      t.datetime :day
      t.string :name
      t.boolean :active

      t.timestamps
    end
  end
end

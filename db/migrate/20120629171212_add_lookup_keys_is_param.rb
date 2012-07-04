class AddLookupKeysIsParam < ActiveRecord::Migration
  def self.up
    add_column :lookup_keys, :is_param, :boolean, :default => false
    add_column :lookup_keys, :is_mandatory, :boolean, :default => false
  end

  def self.down
    remove_column :lookup_keys, :is_param
    remove_column :lookup_keys, :is_mandatory
  end
end

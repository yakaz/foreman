class AddLookupKeysIsParam < ActiveRecord::Migration
  def self.up
    add_column :lookup_keys, :is_param, :boolean, :default => false
  end

  def self.down
    remove_column :lookup_keys, :is_param
  end
end

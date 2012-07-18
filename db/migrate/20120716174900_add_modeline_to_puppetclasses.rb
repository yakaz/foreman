class AddModelineToPuppetclasses < ActiveRecord::Migration
  def self.up
    add_column :puppetclasses, :modeline, :text
  end

  def self.down
    remove_column :puppetclasses, :modeline
  end
end

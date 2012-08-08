class RemoveOperatingsystemsPuppetclassesJoinTable < ActiveRecord::Migration

  def self.up
    drop_table :operatingsystems_puppetclasses
  end

  def self.down
    create_table :operatingsystems_puppetclasses, :id => false do |t|
      t.references :puppetclass, :null => false
      t.references :operatingsystem, :null => false
    end
  end

end

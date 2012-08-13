require 'migration_test_helper'

class PuppetclassesBelongToEnvironmentsMigrationTest < ActiveRecord::MigrationTestCase

  @@migration::REDEFINED_CLASSES.each do |klass|
    ['', 'Base', 'Old', 'New'].each do |prefix|
      c = prefix+klass
      const_set(c, @@migration.const_get(c)) if @@migration.const_defined? c
    end
  end

  class OldEnvironmentsPuppetclass < ActiveRecord::Base
    set_table_name 'environments_puppetclasses'
    belongs_to :environment, :class_name => 'PuppetclassesBelongToEnvironments::OldEnvironment'
    belongs_to :puppetclass, :class_name => 'PuppetclassesBelongToEnvironments::Pupperclass'
  end

  def setup
    init_clear_database
    put_migration_in_intermediate_state
    init_setup_instances
  end

  def init_clear_database
    LookupValue.delete_all
    LookupKey.delete_all
    Puppetclass.delete_all
    Host.delete_all
    Hostgroup.delete_all
    Environment.delete_all
    OldEnvironmentsPuppetclass.delete_all
  end

  def put_migration_in_intermediate_state
    # In order to test both the previous and final state,
    # we must get the database in the intermediate state:
    # both the environments_puppetclasses join table
    # and the puppetclasses.environment_id column,
    # must be present.
    #
    # Remember we can only test the migration
    # if it has not already been played.
    # Hence we are in the "down" state.
    #
    # However, we would like to get into the intermediate state,
    # so we can both create Old* and New* records.
    #
    # This means we must create the new column,
    # (the join table already exist)
    @migration.up_initialize
    @migration.skip :down, :initialize
    # and prevent both from being destroyed.
    # (we will be testing both directions)
    @migration.skip :up,   :finalize
    @migration.skip :down, :finalize
  end

  def init_setup_instances
    @env_prod = Environment.create! :name => "production"
    @env_dev  = Environment.create! :name => "development"
    @env_foo  = Environment.create! :name => "foo"

    @hg_one = Hostgroup.create! :name => "hg_one"
    @hg_two = Hostgroup.create! :name => "hg_two"

    @h_one = Host.create! :name => "h_one", :environment => @env_prod.name # note that Host.environment
    @h_two = Host.create! :name => "h_two", :environment => @env_foo.name  # is actually a mere string

    # @lk_one_global_one = LookupKey.create! :puppetclass => @pc_one, :key => "lk_one", :is_param => false
    # @lk_one_param_one  = LookupKey.create! :puppetclass => @pc_two, :key => "lk_one", :is_param => true
    # @lk_one_two = LookupKey.create! :key => "lk_two", :is_param => false
    # @lk_two_two = LookupKey.create! :key => "lk_two", :is_param => false
  end

  test "up does not fail" do
    assert_nothing_raised do
      up
    end
  end

  test "up then down does not fail" do
    assert_nothing_raised do
      up
      down
    end
  end

  test "up clones a multi-env puppetclass" do
    pc_one = OldPuppetclass.new :name => "pc_one"
    pc_one.environments << @env_prod.to_old
    pc_one.environments << @env_foo.to_old
    pc_one.save!

    assert_equal 1, OldPuppetclass.count,
      "Setup: one old puppetclass"
    assert_equal 2, pc_one.environments.size,
      "Setup: puppetclass has 2 environments"
    assert_equal [pc_one.id], @env_prod.to_old.puppetclass_ids,
      "Setup: each environment has the puppetclass"
    assert_equal [pc_one.id], @env_foo.to_old.puppetclass_ids,
      "Setup: each environment has the puppetclass"

    up

    assert_equal 2, NewPuppetclass.count,
      "cloned the puppetclass once"

    news = NewPuppetclass.all
    assert_equal pc_one.environments.all.map(&:id).sort, news.map(&:environment_id).sort,
      "NewPuppetclass's environments match the OldPuppetclass environments"
    assert_equal [pc_one.name]*2, news.map(&:name),
      "Name it copied"

    # Take the puppetclass for each environment
    assert_equal 1, @env_prod.to_new.puppetclasses.all.size,
      "Each environment has a puppetclass"
    assert_equal 1, @env_foo .to_new.puppetclasses.all.size,
      "Each environment has a puppetclass"
    assert_not_equal @env_prod.to_new.puppetclasses.all.map(&:id), @env_foo.to_new.puppetclasses.all.map(&:id),
      "Each environment has a different puppetclass"
  end

  test "down merges puppetclasses" do
    pc_one_prod = NewPuppetclass.create! :name => "pc_one", :environment => @env_prod.to_new
    pc_one_foo  = NewPuppetclass.create! :name => "pc_one", :environment => @env_foo .to_new

    assert_equal 2, NewPuppetclass.count,
      "Setup: two puppetclasses"
    assert_equal [pc_one_prod.id], @env_prod.to_new.puppetclasses.all.map(&:id),
      "Setup: production env has the right puppetclass"
    assert_equal [pc_one_foo .id], @env_foo .to_new.puppetclasses.all.map(&:id),
      "Setup: foo env has the right puppetclass"

    down

    assert_equal 1, OldPuppetclass.count,
      "Back to only one puppetclass"

    old_pc = OldPuppetclass.all.first
    assert_equal [@env_prod.id, @env_foo.id].sort, old_pc.environment_ids.sort,
      "Puppetclass belongs to both environments"
  end

end

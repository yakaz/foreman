require 'migration_test_helper'

class PuppetclassesBelongToEnvironmentsMigrationTest < ActiveRecord::MigrationTestCase

  @@migration::REDEFINED_CLASSES.each do |klass|
    ['', 'Base', 'Old', 'New'].each do |prefix|
      c = prefix+klass
      const_set(c, @@migration.const_get(c)) if @@migration.const_defined? c
    end
  end

  def setup
    init_clear_database
    init_setup_instances
  end

  def init_clear_database
    LookupValue.destroy_all
    LookupKey.destroy_all
    Puppetclass.destroy_all
    Host.destroy_all
    Hostgroup.destroy_all
    Environment.destroy_all
  end

  def init_setup_instances
    @env_prod = Environment.create! :name => "production"
    @env_dev  = Environment.create! :name => "development"
    @env_foo  = Environment.create! :name => "foo"

    @hg_one = Hostgroup.create! :name => "hg_one"
    @hg_two = Hostgroup.create! :name => "hg_two"

    @h_one = Host.create! :name => "h_one", :environment => @env_prod.name # note that Host.environment
    @h_two = Host.create! :name => "h_two", :environment => @env_foo.name  # is actually a mere string

    # @pc_one = OldPuppetclass.new :name => "pc_one"
    # @pc_one.environments << @env_prod.to_old
    # @pc_one.environments << @env_foo.to_old
    # @pc_one.save!
    # @pc_two = OldPuppetclass.new :name => "pc_two"
    # @pc_two.environments << @env_prod.to_old
    # @pc_two.environments << @env_foo.to_old
    # @pc_two.save!

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

    up

    assert_equal 2, NewPuppetclass.count

    news = NewPuppetclass.all
    assert_equal pc_one.environment_ids.sort, news.map(&:environment_id).sort,
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

end

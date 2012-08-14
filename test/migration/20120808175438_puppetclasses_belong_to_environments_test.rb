require 'migration_test_helper'

class PuppetclassesBelongToEnvironmentsMigrationTest < ActiveRecord::MigrationTestCase

  @@migration::REDEFINED_CLASSES.each do |klass|
    ['', 'Base', 'Old', 'New'].each do |prefix|
      c = prefix+klass
      const_set(c, @@migration.const_get(c)) if @@migration.const_defined? c
    end
  end if @@migration

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

    @hg_one = Hostgroup.create! :name => "hg_one", :environment_id => @env_prod.id
    @hg_two = Hostgroup.create! :name => "hg_two", :environment_id => @env_foo .id

    @h_one = Host.create! :name => "h_one", :environment => @env_prod.name # note that Host.environment
    @h_two = Host.create! :name => "h_two", :environment => @env_foo.name  # is actually a mere string
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

    new_ones = NewPuppetclass.all
    assert_equal pc_one.environments.all.map(&:id).sort, new_ones.map(&:environment_id).sort,
      "NewPuppetclass's environments match the OldPuppetclass environments"
    assert_equal [pc_one.name]*2, new_ones.map(&:name),
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

  test "up clones lookup-keys and -values" do
    pc_one = OldPuppetclass.new :name => "pc_one"
    pc_one.environments << @env_prod.to_old
    pc_one.environments << @env_foo.to_old
    pc_one.save!

    lk_one = LookupKey.create! :puppetclass => pc_one, :key => "lk_one"
    lv_one = LookupValue.create! :lookup_key => lk_one, :value => "lv_one"

    assert_equal 1, pc_one.lookup_keys.count,
      "Setup: puppetclass has its lookup-key"
    assert_equal 1, lk_one.lookup_values.count,
      "Setup: lookup_key has its lookup-value"
    assert_equal 1, LookupKey.count
      "Setup: only one lookup-key"
    assert_equal 1, LookupValue.count
      "Setup: only one lookup-value"

    up

    assert_equal 2, LookupKey.count,
      "Cloned lookup-keys"
    assert_equal 2, LookupValue.count,
      "Cloned lookup-values"

    new_ones = NewPuppetclass.all
    assert_equal 2, new_ones.map { |pc| pc.lookup_keys.map(&:id) }.flatten.uniq.size,
      "The two puppetclasses have distinct lookup-keys"
    assert_equal 2, new_ones.map { |pc| pc.lookup_keys.map { |lk| lk.lookup_values.map(&:id) }.flatten }.flatten.uniq.size,
      "The two puppetclasses have distinct lookup-values"
  end

  test "down merges identical lookup-keys and -values" do
    pc_one_prod = NewPuppetclass.create! :name => "pc_one", :environment => @env_prod.to_new
    pc_one_foo  = NewPuppetclass.create! :name => "pc_one", :environment => @env_foo .to_new

    lk_one_prod = LookupKey.create! :puppetclass => pc_one_prod, :key => "lk_one"
    lk_one_foo  = LookupKey.create! :puppetclass => pc_one_foo , :key => "lk_one"
    lv_one_prod = LookupValue.create! :lookup_key => lk_one_prod, :value => "lv_one"
    lv_one_foo  = LookupValue.create! :lookup_key => lk_one_foo , :value => "lv_one"

    down

    assert_equal 1, LookupKey.count,
      "Merged lookup-keys"
    assert_equal 1, LookupValue.count,
      "Merged lookup-values"
  end

  test "down noops non-mergeable puppetclasses" do
    pc_one_prod = NewPuppetclass.create! :name => "pc_one", :environment => @env_prod.to_new
    pc_two_foo  = NewPuppetclass.create! :name => "pc_two", :environment => @env_foo .to_new

    down

    assert_equal 2, Puppetclass.count,
      "Independent puppetclasses don't get merged"
  end

  test "down merges separate lookup-keys" do
    pc_one_prod = NewPuppetclass.create! :name => "pc_one", :environment => @env_prod.to_new
    pc_one_foo  = NewPuppetclass.create! :name => "pc_one", :environment => @env_foo .to_new

    lk_one_prod = LookupKey.create! :puppetclass => pc_one_prod, :key => "lk_one"
    lk_two_foo  = LookupKey.create! :puppetclass => pc_one_foo , :key => "lk_two"
    lv_one_prod = LookupValue.create! :lookup_key => lk_one_prod, :value => "lv_one"
    lv_one_foo  = LookupValue.create! :lookup_key => lk_two_foo , :value => "lv_one"

    down

    assert_equal 2, LookupKey.count,
      "Independent lookup-keys don't get merged"
    assert_equal 2, LookupValue.count,
      "Independent lookup-values don't get merged"
  end

  test "down merges separate lookup-values" do
    pc_one_prod = NewPuppetclass.create! :name => "pc_one", :environment => @env_prod.to_new
    pc_one_foo  = NewPuppetclass.create! :name => "pc_one", :environment => @env_foo .to_new

    lk_one_prod = LookupKey.create! :puppetclass => pc_one_prod, :key => "lk_one"
    lk_one_foo  = LookupKey.create! :puppetclass => pc_one_foo , :key => "lk_one"
    lv_one_prod = LookupValue.create! :lookup_key => lk_one_prod, :value => "lv_one", :match => "fqdn=foo"
    lv_two_foo  = LookupValue.create! :lookup_key => lk_one_foo , :value => "lv_two", :match => "fqdn=bar"

    down

    assert_equal 1, LookupKey.count,
      "Merged lookup-keys"
    assert_equal 2, LookupValue.count,
      "Complementary lookup-values don't get merged into a single one"
  end

  test "down merges lookup-keys basic properties" do
    pc_one_prod = NewPuppetclass.create! :name => "pc_one", :environment => @env_prod.to_new
    pc_one_foo  = NewPuppetclass.create! :name => "pc_one", :environment => @env_foo .to_new

    lk_one_prod = LookupKey.create! :puppetclass => pc_one_prod, :key => "lk_one", :validator_type => 'list', :default_value => 'a', :description => 'b', :validator_rule => 'c'
    lk_one_foo  = LookupKey.create! :puppetclass => pc_one_foo , :key => "lk_one", :validator_type => 'list', :default_value => nil, :description => nil, :validator_rule => nil
    lk_two_prod = LookupKey.create! :puppetclass => pc_one_prod, :key => "lk_two", :validator_type => 'list', :default_value => nil, :description => nil, :validator_rule => nil
    lk_two_foo  = LookupKey.create! :puppetclass => pc_one_foo , :key => "lk_two", :validator_type => 'list', :default_value => 'd', :description => 'e', :validator_rule => 'f'

    down

    assert_equal 2, LookupKey.count,
      "Merged lookup-keys"

    lk_one_new = LookupKey.where(:key => lk_one_prod.key).first
    lk_two_new = LookupKey.where(:key => lk_two_prod.key).first
    assert_not_nil lk_one_new
    assert_not_nil lk_two_new
    assert_equal 'a', lk_one_new.default_value
    assert_equal 'b', lk_one_new.description
    assert_equal 'c', lk_one_new.validator_rule
    assert_equal 'd', lk_two_new.default_value
    assert_equal 'e', lk_two_new.description
    assert_equal 'f', lk_two_new.validator_rule
  end

  test "down merges lookup-keys mandatory and path properties" do
    pc_one_prod = NewPuppetclass.create! :name => "pc_one", :environment => @env_prod.to_new
    pc_one_foo  = NewPuppetclass.create! :name => "pc_one", :environment => @env_foo .to_new

    lk_one_prod = LookupKey.create! :puppetclass => pc_one_prod, :key => "lk_one", :is_mandatory => false, :path => ['a','c'    ]
    lk_one_foo  = LookupKey.create! :puppetclass => pc_one_foo , :key => "lk_one", :is_mandatory => true , :path => ['a',    'b']
    lk_two_prod = LookupKey.create! :puppetclass => pc_one_prod, :key => "lk_two", :is_mandatory => true , :path => ['a','b'    ]
    lk_two_foo  = LookupKey.create! :puppetclass => pc_one_foo , :key => "lk_two", :is_mandatory => false, :path => ['a',    'c']

    down

    assert_equal 2, LookupKey.count,
      "Merged lookup-keys"

    lk_one_new = LookupKey.where(:key => lk_one_prod.key).first
    lk_two_new = LookupKey.where(:key => lk_two_prod.key).first
    assert_not_nil lk_one_new
    assert_not_nil lk_two_new
    assert_equal true, lk_one_new.is_mandatory
    assert_equal [['a'], ['c'], ['b']], lk_one_new.path_elements
    assert_equal true, lk_two_new.is_mandatory
    assert_equal [['a'], ['b'], ['c']], lk_two_new.path_elements
  end

  test "down merges lookup-keys within is_param scope" do
    pc_one_prod = NewPuppetclass.create! :name => "pc_one", :environment => @env_prod.to_new
    pc_one_foo  = NewPuppetclass.create! :name => "pc_one", :environment => @env_foo .to_new

    lk_one_global_prod = LookupKey.create! :puppetclass => pc_one_prod, :key => "lk_one", :is_param => false, :default_value => 'a', :description => nil
    lk_one_global_foo  = LookupKey.create! :puppetclass => pc_one_foo , :key => "lk_one", :is_param => false, :default_value => nil, :description => 'b'
    lv_one_global_prod = LookupValue.create! :lookup_key => lk_one_global_prod, :value => "lv_one"
    lv_one_global_foo  = LookupValue.create! :lookup_key => lk_one_global_foo , :value => "lv_one"

    lk_one_param_prod  = LookupKey.create! :puppetclass => pc_one_prod, :key => "lk_one", :is_param => true , :default_value => 'c', :description => nil
    lk_one_param_foo   = LookupKey.create! :puppetclass => pc_one_foo , :key => "lk_one", :is_param => true , :default_value => nil, :description => 'd'
    lv_one_param_prod  = LookupValue.create! :lookup_key => lk_one_param_prod,  :value => "lv_one_too"
    lv_one_param_foo   = LookupValue.create! :lookup_key => lk_one_param_foo ,  :value => "lv_one_too"

    assert_equal 1, [lk_one_global_prod, lk_one_global_foo, lk_one_param_prod, lk_one_param_foo].map(&:key).uniq.size,
      "Setup: All lookup-keys have the same name"

    down

    assert_equal 2, LookupKey.count,
      "Merged lookup-keys"
    assert_equal 2, LookupValue.count,
      "Merged lookup-values"

    lk_one_global_new = LookupKey.where(:key => "lk_one", :is_param => false).first
    lk_one_param_new  = LookupKey.where(:key => "lk_one", :is_param => true ).first
    assert_not_nil lk_one_global_new
    assert_not_nil lk_one_param_new
    assert_equal 'a', lk_one_global_new.default_value
    assert_equal 'b', lk_one_global_new.description
    assert_equal 'lv_one',     lk_one_global_new.lookup_values.first.value
    assert_equal 'c', lk_one_param_new. default_value
    assert_equal 'd', lk_one_param_new. description
    assert_equal 'lv_one_too', lk_one_param_new .lookup_values.first.value
  end

  test "up selects the right puppetclass clone" do
    pc_one = OldPuppetclass.create! :name => "pc_one", :environment_ids => [@env_prod.id, @env_foo.id, @env_dev.id]
    @h_one.puppetclass_ids = [pc_one.id]
    @h_one.save!
    @h_two.puppetclass_ids = [pc_one.id]
    @h_two.save!
    @hg_one.puppetclass_ids = [pc_one.id]
    @hg_one.save!
    @hg_two.puppetclass_ids = [pc_one.id]
    @hg_two.save!

    up

    @h_one.clear_association_cache
    @h_two.clear_association_cache
    @hg_one.clear_association_cache
    @hg_two.clear_association_cache

    assert_equal 3, NewPuppetclass.count,
      "Puppetclass got cloned"

    assert_not_nil pc_one_prod = NewPuppetclass.where(:environment_id => @env_prod.id).first
    assert_not_nil pc_one_foo  = NewPuppetclass.where(:environment_id => @env_foo .id).first
    assert_not_nil pc_one_dev  = NewPuppetclass.where(:environment_id => @env_dev .id).first

    assert_equal [pc_one_prod.id], @h_one.puppetclass_ids,
      "Host took the matching puppetclass (one, #{@h_one.environment})"
    assert_equal [pc_one_foo .id], @h_two.puppetclass_ids,
      "Host took the matching puppetclass (two, #{@h_two.environment})"
    assert_equal [pc_one_prod.id], @hg_one.puppetclass_ids,
      "Hostgroup took the matching puppetclass (one, #{@hg_one.environment.name})"
    assert_equal [pc_one_foo .id], @hg_two.puppetclass_ids,
      "Hostgroup took the matching puppetclass (two, #{@hg_two.environment.name})"
  end

  test "down merges puppetclasses references" do
    pc_one_prod = NewPuppetclass.create! :name => "pc_one", :environment => @env_prod.to_new
    pc_one_foo  = NewPuppetclass.create! :name => "pc_one", :environment => @env_foo .to_new

    @h_one.puppetclass_ids = [pc_one_prod.id]
    @h_one.save!
    @h_two.puppetclass_ids = [pc_one_foo .id]
    @h_two.save!
    @hg_one.puppetclass_ids = [pc_one_prod.id]
    @hg_one.save!
    @hg_two.puppetclass_ids = [pc_one_foo .id]
    @hg_two.save!

    down

    @h_one.clear_association_cache
    @h_two.clear_association_cache
    @hg_one.clear_association_cache
    @hg_two.clear_association_cache

    assert_equal 1, OldPuppetclass.count,
      "Puppetclasses got merged"
    assert_not_nil pc_one_old = OldPuppetclass.first

    assert_equal [pc_one_old.id], @h_one.puppetclass_ids,
      "Host took the merged puppetclass (one, #{@h_one.environment})"
    assert_equal [pc_one_old.id], @h_two.puppetclass_ids,
      "Host took the merged puppetclass (two, #{@h_two.environment})"
    assert_equal [pc_one_old.id], @hg_one.puppetclass_ids,
      "Hostgroup took the merged puppetclass (one, #{@hg_one.environment.name})"
    assert_equal [pc_one_old.id], @hg_two.puppetclass_ids,
      "Hostgroup took the merged puppetclass (two, #{@hg_two.environment.name})"
  end

  test "down unassigns unmergeable lookup-keys" do
    pc_one_prod = NewPuppetclass.create! :name => "pc_one", :environment => @env_prod.to_new
    pc_one_foo  = NewPuppetclass.create! :name => "pc_one", :environment => @env_foo .to_new

    lk_one_prod = LookupKey.create! :puppetclass => pc_one_prod, :key => "lk_one", :validator_type => 'list'
    lk_one_foo  = LookupKey.create! :puppetclass => pc_one_foo , :key => "lk_one", :validator_type => 'string'

    down

    assert_equal 2, LookupKey.count,
      "Merged lookup-key + unassigned lookup-key"

    lks = LookupKey.all
    if lks.first.puppetclass_id.nil?
      lk_one_new = lks.pop
      lk_one_nil = lks.pop
    else
      lk_one_new = lks.shift
      lk_one_nil = lks.shift
    end
    assert_not_nil lk_one_new
    assert_not_nil lk_one_nil
    assert_not_nil lk_one_new.puppetclass_id,
      "We have an assigned key"
    assert_nil     lk_one_nil.puppetclass_id,
      "We have an unassigned key"
  end

end

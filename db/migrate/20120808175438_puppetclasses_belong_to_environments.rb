class PuppetclassesBelongToEnvironments < ActiveRecord::Migration

  def method_missing m, *args, &block
    # Forward to the class
    if block_given?
      self.class.send(m, *args) {|*args| block.call(*args)}
    else
      self.class.send(m, *args)
    end
  end

  def skip direction, part
    instance_variable_set :"@#{direction}_#{part}_done", true
  end

  def up_initialize
    return if @up_initialize_done

    add_column :puppetclasses, :environment_id, :integer

    @up_initialize_done = true
  end

  def up_migrate
    return if @up_migrate_done

    # Duplicate puppetclasses: one per environment
    pc_id_to_clone_ids_by_env = {} # mapping to find the new puppetclass id
                                   # corresponding to the desired environment,
                                   # from the previous puppetclass id
    OldPuppetclass.all.each do |old_puppetclass|
      env_ids = old_puppetclass.environment_ids
      first_env_id = env_ids.shift
      mapping = pc_id_to_clone_ids_by_env[old_puppetclass.id] = {}
      mapping[first_env_id] = old_puppetclass.id
      new_puppetclass = old_puppetclass.to_new
      env_ids.each do |new_env_id|
        new_pc = new_puppetclass.clone
        new_pc.environment_id = new_env_id
        new_pc.save!
        mapping[new_env_id] = new_pc.id
      end
      new_puppetclass.environment_id = first_env_id
      new_puppetclass.save!
    end

    # Redirect related objects to the puppetclasses from the right environment
    Host.all.each do |h|
      h.puppetclass_ids = h.puppetclass_ids.map { |pc_id| pc_id_to_clone_ids_by_env[pc_id][h.environment_id] }
      h.save! :validate => false
    end
    Hostgroup.all.each do |hg|
      hg.puppetclass_ids = hg.puppetclass_ids.map { |pc_id| pc_id_to_clone_ids_by_env[pc_id][hg.environment_id] }
      hg.save! :validate => false
    end

    @up_migrate_done = true
  end

  def up_finalize
    return if @up_finalize_done

    drop_table :environments_puppetclasses

    @up_finalize_done = true
  end

  def self.up
    new.up
  end
  def up
    # Method split down for better testability
    up_initialize
    up_migrate
    up_finalize
  end
  alias_method :up_with_benchmarks, :up
  alias_method :up_without_benchmarks, :up

  def down_initialize
    return if @down_initialize_done

    create_table :environments_puppetclasses, :id => false do |t|
      t.references :puppetclass, :null => false
      t.references :environment, :null => false
    end

    @down_initialize_done = true
  end

  def down_migrate
    return if @down_migrate_done

    pc_id_to_name = {} # note id to name mapping, to reduce SQL query usage
    # Note what puppetclass name belong to what environments under what id
    pc_name_to_env_id_pc_id_mapping = Hash.new { |h,k| h[k] = {} }
    NewPuppetclass.all.each do |new_puppetclass|
      pc_id_to_name[new_puppetclass.id] = new_puppetclass.name
      mapping = pc_name_to_env_id_pc_id_mapping[new_puppetclass.name]
      mapping[new_puppetclass.environment_id] = new_puppetclass.id
      if mapping["new_id"].nil? or new_puppetclass.id < mapping["new_id"]
        # Don't just take any id as the id to retain,
        # try to keep the same as the previous one,
        # which is simply done by taking the least id
        # (as they usually auto increment)
        mapping["new_id"] = new_puppetclass.id
      end
    end

    # Merge references
    Host.all.each do |h|
      h.puppetclass_ids = h.puppetclass_ids.map { |id| pc_name_to_env_id_pc_id_mapping[pc_id_to_name[id]]["new_id"] }
      h.save! :validate => false
    end
    Hostgroup.all.each do |hg|
      hg.puppetclass_ids = hg.puppetclass_ids.map { |id| pc_name_to_env_id_pc_id_mapping[pc_id_to_name[id]]["new_id"] }
      hg.save! :validate => false
    end

    # Merge lookup keys
    pc_name_to_env_id_pc_id_mapping.each do |_,_group|
      group = _group.dup
      target_id = group.delete "new_id"
      group.delete_if { |k,v| v == target_id }
      target = OldPuppetclass.find_by_id target_id
      group.each do |_,pc_id|
        current = NewPuppetclass.find_by_id pc_id
        current.lookup_keys.all.each do |current_lookup_key|
          target_lookup_key = target.lookup_keys.where(:key => current_lookup_key.key, :is_param => current_lookup_key.is_param).first
          if target_lookup_key.nil?
            target.lookup_keys << current_lookup_key
          elsif target_lookup_key.validator_type == current_lookup_key.validator_type
            # Merge some properties, if interesting
            [:default_value, :description, :validator_rule].each do |prop|
              if target_lookup_key.send(prop).blank? and !current_lookup_key.send(prop).blank?
                target_lookup_key.send(prop+'=', current_lookup_key.send(prop))
              end
            end
            # Merge path
            target_lookup_key.path = (target_lookup_key.path_elements + current_lookup_key.path_elements).uniq
            target_lookup_key.is_mandatory = true if current_lookup_key.is_mandatory
            # Merge lookup values
            current_lookup_key.lookup_values.all.each do |current_lookup_value|
              debugger
              target_lookup_value = target_lookup_key.lookup_values.where(:match => current_lookup_value.match).first
              if target_lookup_value.nil?
                target_lookup_key.lookup_values << current_lookup_value
              else
                # Drop, as values can't be null, there is nothing to merge
                current_lookup_value.destroy
              end
            end
            # Merged, can now be deleted
            current_lookup_key.destroy
          else
            # Drop if the types don't match
            current_lookup_key.destroy
          end
        end
      end
    end

    # Remove old puppetclasses
    pc_name_to_env_id_pc_id_mapping.each do |_,_group|
      group = _group.dup
      survivor_id = group.delete "new_id"
      group.delete_if { |k,v| v == survivor_id }
      group.each do |_,pc_id|
        NewPuppetclass.destroy pc_id
      end
    end

    # Merging environments of puppetclasses
    pc_name_to_env_id_pc_id_mapping.each do |_,_group|
      group = _group.dup
      target_id = group.delete "new_id"
      target = OldPuppetclass.find_by_id target_id
      target.environment_ids = group.each_key.to_a
      target.save!
    end

    @down_migrate_done = true
  end

  def down_finalize
    return if @down_finalize_done

    remove_column :puppetclasses, :environment_id

    @down_finalize_done = true
  end

  def self.down
    new.down
  end
  def down
    # Method split down for better testability
    down_initialize
    down_migrate
    down_finalize
  end
  alias_method :down_with_benchmarks, :down
  alias_method :down_without_benchmarks, :down

  #
  # Define the necessary model here.
  #
  # We should/can not mix the classes defined here,
  # with classes defined in the app/models/ folder,
  # as the class test will fail (same name, but different classes).
  #

  REDEFINED_CLASSES = %w(Environment Puppetclass LookupKey LookupValue Hostgroup Host) # without the Old/New prefixes

  # Returns instances of the class, with another prefix.
  # Eg.: Can be used to convert a OldModel to NewModel, or to Model.
  module PrefixConvertors
    def to_base
      to_prefix ''
    end

    def to_old
      to_prefix 'Old'
    end

    def to_new
      to_prefix 'New'
    end

    private
    def strip_prefix class_name
      class_name.sub /(?:Old|New)([^:]*)$/, '\1'
    end

    def add_prefix class_name, prefix
      class_name.sub /^(.*::)([^:]*)$/, "\\1#{prefix}\\2"
    end

    def target_class prefix
      add_prefix(strip_prefix(self.class.name), prefix).constantize
    end

    def to_prefix prefix
      new_class = target_class prefix
      return new_class.new self.attributes if self.id.blank?
      new_class.find self.id
    end
  end

  class Environment < ActiveRecord::Base
    include PrefixConvertors
    set_table_name "environments"
  end

  class OldEnvironment < Environment
    has_and_belongs_to_many :puppetclasses, :class_name => 'PuppetclassesBelongToEnvironments::OldPuppetclass', :join_table => 'environments_puppetclasses', :association_foreign_key => 'puppetclass_id', :foreign_key => 'environment_id'
  end

  class NewEnvironment < Environment
    has_many :puppetclasses, :class_name => 'PuppetclassesBelongToEnvironments::NewPuppetclass', :inverse_of => :environment, :foreign_key => 'environment_id'
  end

  class Puppetclass < ActiveRecord::Base
    include PrefixConvertors
    set_table_name "puppetclasses"
    has_many :lookup_keys, :inverse_of => :puppetclass, :foreign_key => 'puppetclass_id'
    has_many :host_classes, :dependent => :destroy, :inverse_of => :puppetclass
    has_many :hosts, :through => :host_classes, :inverse_of => :puppetclasses
    has_and_belongs_to_many :hostgroups
  end

  class OldPuppetclass < Puppetclass
    has_and_belongs_to_many :environments, :class_name => 'PuppetclassesBelongToEnvironments::OldEnvironment', :join_table => 'environments_puppetclasses', :association_foreign_key => 'environment_id', :foreign_key => 'puppetclass_id'
  end

  class NewPuppetclass < Puppetclass
    belongs_to :environment, :class_name => 'PuppetclassesBelongToEnvironments::NewEnvironment', :inverse_of => :puppetclasses
    def clone
      new = super
      new.hostgroups = hostgroups
      new.host_classes = host_classes
      new.hosts = hosts
      new.lookup_keys = lookup_keys.map(&:clone)
      new
    end
  end

  class LookupKey < ActiveRecord::Base
    belongs_to :puppetclass, :inverse_of => :lookup_keys
    has_many :lookup_values, :inverse_of => :lookup_key

    KEY_DELM = ","
    EQ_DELM  = "="

    def clone
      new = super
      new.lookup_values = lookup_values.map(&:clone)
      new
    end

    def path
      read_attribute(:path) || array2path(Setting["Default_variables_Lookup_Path"])
    end

    def path=(v)
      v = array2path v if v.is_a? Array
      return if v == array2path(Setting["Default_variables_Lookup_Path"])
      write_attribute(:path, v)
    end

    def path_elements
      path.split.map do |paths|
        paths.split(KEY_DELM).map do |element|
          element
        end
      end
    end

    private

    def array2path array
      raise "invalid path" unless array.is_a?(Array)
      array.map do |sub_array|
        sub_array.is_a?(Array) ? sub_array.join(KEY_DELM) : sub_array
      end.join("\n")
    end

  end

  class LookupValue < ActiveRecord::Base
    belongs_to :lookup_key, :inverse_of => :lookup_values
  end

  class Hostgroup < ActiveRecord::Base
    has_many :hosts, :inverse_of => :hostgroup
    has_and_belongs_to_many :puppetclasses
  end

  class HostClass < ActiveRecord::Base
    belongs_to :host
    belongs_to :puppetclass
  end

  class Host < ActiveRecord::Base
    belongs_to :hostgroup, :inverse_of => :hosts
    has_many :host_classes, :dependent => :destroy, :inverse_of => :host
    has_many :puppetclasses, :through => :host_classes, :inverse_of => :hosts
  end

end

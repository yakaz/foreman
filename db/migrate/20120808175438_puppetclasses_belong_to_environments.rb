class PuppetclassesBelongToEnvironments < ActiveRecord::Migration

  # XXX
  # # Provide an object representation of the to-be-deleted
  # # puppetclasses<=>environments relation
  # class EnvironmentsPuppetclass < ActiveRecord::Base
  #   belongs_to :environment
  #   belongs_to :puppetclass
  # end

  # Register both the old relation that will be missing with the new code,
  # but is necessary to revert the migration.
  Puppetclass.class_eval {
    belongs_to :environment
    has_and_belongs_to_many :environments
  }

  def self.up
    add_column :puppetclasses, :environment_id, :integer

    # Duplicate puppetclasses: one per environment
    pc_id_to_clone_ids_by_env = {} # mapping to find the new puppetclass id
                                   # corresponding to the desired environment,
                                   # from the previous puppetclass id
    Puppetclass.all.each do |puppetclass|
      env_ids = puppetclass.environment_ids # XXX EnvironmentsPuppetclass.where(:puppetclass_id => puppetclass.id).map(&:environment_id)
      first_env_id = env_ids.shift
      mapping = pc_id_to_clone_ids_by_env[puppetclass.id] = {}
      mapping[first_env_id] = puppetclass.id
      env_ids.each do |new_env_id|
        new_pc = puppetclass.clone
        new_pc.environment_id = new_env_id
        new_pc.save!
        mapping[new_env_id] = new_pc.id
      end
      puppetclass.environment_id = first_env_id
      puppetclass.save!
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

    drop_table :environments_puppetclasses
  end

  def self.down
    create_table :environments_puppetclasses, :id => false do |t|
      t.references :puppetclass, :null => false
      t.references :environment, :null => false
    end

    pc_id_to_name = {} # note id to name mapping, to reduce SQL query usage
    # Note what puppetclass name belong to what environments under what id
    pc_name_to_env_id_pc_id_mapping = Hash.new { |h,k| h[k] = {} }
    Puppetclass.all.each do |puppetclass|
      pc_id_to_name[puppetclass.id] = puppetclass.name
      mapping = pc_name_to_env_id_pc_id_mapping[puppetclass.name]
      mapping[puppetclass.environment_id] = puppetclass.id
      if mapping["new_id"].nil? or puppetclass.id < mapping["new_id"]
        # Don't just take any id as the id to retain,
        # try to keep the same as the previous one,
        # which is simply done by taking the least id
        # (as they usually auto increment)
        mapping["new_id"] = puppetclass.id
      end
    end

    # Merge references
    Host.all.each do |h|
      h.puppetclass_ids.map { |id| pc_name_to_env_id_pc_id_mapping[pc_id_to_name[id]]["new_id"] }
      h.save! :validate => false
    end
    Hostgroup.all.each do |hg|
      hg.puppetclass_ids.map { |id| pc_name_to_env_id_pc_id_mapping[pc_id_to_name[id]]["new_id"] }
      hg.save! :validate => false
    end

    # Merge lookup keys
    pc_name_to_env_id_pc_id_mapping.each do |_,group|
      target_id = group.delete "new_id"
      target = Puppetclass.find_by_id target_id
      group.delete target_id
      group.each do |_,pc_id|
        current = Puppetclass.find_by_id pc_id
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
            path_elements_of = lambda { |lookup_key|
              lookup_key.instance_eval { path_elements }
            }
            target_lookup_key.path = (path_elements_of.call(target_lookup_key) + path_elements_of.call(current_lookup_key)).uniq
            target_lookup_key.is_mandatory = true if current_lookup_key.is_mandatory
            # Merge lookup values
            current_lookup_key.lookup_values.all.each do |current_lookup_value|
              target_lookup_value = target_lookup_key.lookup_values.where(:matcher => current_lookup_value.matcher)
              if target_lookup_value.nil?
                target_lookup_key.lookup_values << current_lookup_value
              else
                # Drop, as values can't be null
              end
            end
          else
            # Drop if the types don't match
          end
        end
      end
    end

    # Remove old puppetclasses
    pc_name_to_env_id_pc_id_mapping.each do |_,group|
      survivor_id = group.delete "new_id"
      group.delete survivor_id
      group.each do |_,pc_id|
        Puppetclass.destroy pc_id
      end
    end

    remove_column :puppetclasses, :environment_id
  end

end

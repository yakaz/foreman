class Environment < ActiveRecord::Base
  has_and_belongs_to_many :puppetclasses
  has_many :hosts
  validates_presence_of :name
  validates_uniqueness_of :name
  validates_format_of :name, :with => /^[\w\d]+$/, :message => "is alphanumeric and cannot contain spaces"
  has_many :config_templates, :through => :template_combinations, :dependent => :destroy
  has_many :template_combinations

  before_destroy EnsureNotUsedBy.new(:hosts)
  default_scope :order => 'LOWER(environments.name)'

  scoped_search :on => :name, :complete_value => :true

  def to_param
    name
  end

  class << self

    # returns an hash of all puppet environments and their relative paths
    def puppetEnvs proxy = nil
      #TODO: think of a better way to model multiple puppet proxies
      url = (proxy || find_import_proxies.first).try(:url)
      raise "Can't find a valid Foreman Proxy with a Puppet feature" if url.blank?
      proxy = ProxyAPI::Puppet.new :url => url
      HashWithIndifferentAccess[proxy.environments.map { |e|
        [e, HashWithIndifferentAccess[proxy.classes(e).map {|k|
          klass = k.keys.first
          [klass, {
            :params   => k[klass]["params"],
            :modeline => k[klass]["modeline"] ? ActiveSupport::JSON.decode(k[klass]["modeline"]) : {}
          }]
        }]]
      }]
    end

    # Imports all Environments and classes from Puppet modules
    def importClasses proxy_id
      # Build two hashes representing the on-disk and in-database, env to classes associations
      # Create a representation of the puppet configuration where the environments are hash keys and the classes are sorted lists
      disk_tree         = puppetEnvs SmartProxy.find(proxy_id)
      disk_tree.default = []

      # Create a representation of the foreman configuration where the environments are hash keys and the classes are sorted lists
      db_tree           = HashWithIndifferentAccess[Environment.all.map { |e|
        [e.name, HashWithIndifferentAccess[e.puppetclasses.all.map {|pc|
          [pc.name, {
            :params   => HashWithIndifferentAccess[pc.lookup_keys.all.map {|k| [k.key, k.default_value] if k.is_param}.compact],
            :modeline => pc.modeline
          }]
        }]]
      }]
      db_tree.default   = []

      changes = { "new" => { }, "obsolete" => { }, "updated" => { } }
      # Generate the difference between the on-disk and database configuration
      for env in db_tree.keys
        # Show the environment if there are classes in the db that do not exist on disk
        # OR if there is no mention of the class on-disk
        surplus_db_classes = db_tree[env].dup.delete_if { |k,v| disk_tree[env].has_key? k }
        surplus_db_classes["_destroy_"] = "_destroy_" unless disk_tree.has_key?(env) # We need to distinguish between an empty and an obsolete env
        changes["obsolete"][env] = surplus_db_classes if surplus_db_classes.size > 0
      end
      for env in disk_tree.keys
        extra_disk_classes = disk_tree[env].dup.delete_if { |k,v| db_tree[env].has_key? k }
        # Show the environment if there are new classes compared to the db
        # OR if the environment has no puppetclasses but does not exist in the db
        changes["new"][env] = extra_disk_classes if (extra_disk_classes.size > 0 or (disk_tree[env].size == 0 and Environment.find_by_name(env).nil?))
      end
      for env_str in db_tree.keys & disk_tree.keys
        env = Environment.find_by_name(env_str)
        db_params = db_tree[env_str] # read the already fetched parameters
        updated_classes = HashWithIndifferentAccess[
          db_params.map do |klass, attributes|
            disk_attributes = disk_tree[env_str][klass]
            if disk_attributes
              actions = {}
              # Compare parameters.
              params = attributes[:params]
              disk_params = disk_attributes[:params]
              param_updates = {}
              surplus_db_params = params.dup.delete_if { |p,v| disk_params.has_key? p }
              param_updates['obsolete'] = surplus_db_params if surplus_db_params.size > 0
              extra_disk_params = disk_params.dup.delete_if { |p,v| params.has_key? p }
              param_updates['new'] = extra_disk_params if extra_disk_params.size > 0
              updated_params = HashWithIndifferentAccess[disk_params.select { |p,v| (params.has_key? p) && (params[p] != v) }]
              param_updates['updated'] = updated_params if updated_params.size > 0
              actions[:params] = param_updates if param_updates.size > 0
              # Compare modelines.
              modeline = attributes[:modeline]
              disk_modeline = disk_attributes[:modeline]
              actions[:modeline] = disk_modeline if modeline != disk_modeline
              [ klass, actions ] if actions.size > 0
            end
          end.compact
        ]
        changes["updated"][env_str] = updated_classes if updated_classes.size > 0
      end

      # Remove environments that are in config/ignored_environments.yml
      ignored_file = File.join(Rails.root.to_s, "config", "ignored_environments.yml")
      if File.exist? ignored_file
        ignored = YAML.load_file ignored_file
        for env in ignored[:new]
          changes["new"].delete env
        end
        for env in ignored[:obsolete]
          changes["obsolete"].delete env
        end
        for env in ignored[:updated]
          changes["updated"].delete env
        end
      end
      changes
    end

    # Update the environments and puppetclasses based upon the user's selection
    # It does a best attempt and can fail to perform all operations due to the
    # user requesting impossible selections. Repeat the operation if errors are
    # shown, after fixing the request.
    # +changed+ : Hash with two keys: :new and :obsolete.
    #               changed[:/new|obsolete/] is and Array of Strings
    # Returns   : Array of Strings containing all record errors
    def obsolete_and_new changed
      changed        ||= { }
      @import_errors = []

      # Now we add environments and associations
      for env_str in changed[:new].keys
        env = Environment.find_or_create_by_name env_str
        if env.valid? and !env.new_record?
          begin
            pclasses = ActiveSupport::JSON.decode(changed[:new][env_str])
          rescue => e
            @import_errors << "Failed to eval #{changed[:new][env_str]} as a hash:" + e.message
            next
          end
          pclasses.each do |pclass,attributes|
            pc = Puppetclass.find_or_create_by_name pclass
            if pc.errors.empty?
              env.puppetclasses << pc
              parameters = attributes["params"]
              parameters.each do |param_str, value|
                key = LookupKey.create :key => param_str, :puppetclass_id => pc.id, :is_param => true, :is_mandatory => value.nil?, :default_value => value, :validator_type => LookupKey.suggest_validator_type(value)
                if key.errors.empty?
                  pc.lookup_keys << key
                else
                  @import_errors += key.errors.map(&:to_s)
                end
              end
              if attributes.has_key?("modeline")
                pc.modeline = attributes["modeline"]
                pc.save!
              end
            else
              @import_errors += pc.errors.map(&:to_s)
            end
          end
          env.save!
        else
          @import_errors << "Unable to find or create environment #{env_str} in the foreman database"
        end
      end if changed[:new]

      # Remove the obsoleted stuff
      for env_str in changed[:obsolete].keys
        env = Environment.find_by_name env_str
        if env
          begin
            pclasses = ActiveSupport::JSON.decode(changed[:obsolete][env_str])
          rescue => e
            @import_errors << "Failed to eval #{changed[:obsolete][env_str]} as a hash:" + e.message
            next
          end
          pclass = ""
          for pclass in pclasses.keys
            unless pclass == "_destroy_"
              pc = Puppetclass.find_by_name pclass
              if pc.nil?
                @import_errors << "Unable to find puppet class #{pclass} in the foreman database"
              else
                env.puppetclasses.delete pc
                unless pc.environments.any? or pc.hosts.any?
                  pc.destroy
                  @import_errors += pc.errors.full_messages unless pc.errors.empty?
                end
              end
            end
          end
          if pclasses.has_key? "_destroy_"
            env.destroy
            @import_errors += env.errors.full_messages unless env.errors.empty?
          else
            env.save!
          end
        else
          @import_errors << "Unable to find environment #{env_str} in the foreman database"
        end
      end if changed[:obsolete]

      # Update puppet classes with new parameters or modeline
      for env_str in changed[:updated].keys
        env = Environment.find_by_name env_str
        if env.valid? and !env.new_record?
          begin
            pclasses = ActiveSupport::JSON.decode(changed[:updated][env_str])
          rescue => e
            @import_errors << "Failed to eval #{changed[:updated][env_str]} as a hash:" + e.message
            next
          end
          # Process each parameter update
          pclasses.each do |pclass, attributes|
            pc = Puppetclass.find_by_name pclass
            if pc.errors.empty?
              changed_params = attributes["params"]
              if changed_params
                # Add new parameters
                changed_params["new"].each do |param_str, value|
                  key = LookupKey.create :key => param_str, :puppetclass_id => pc.id, :is_param => true, :is_mandatory => value.nil?, :default_value => value, :validator_type => LookupKey.suggest_validator_type(value)
                  if key.errors.empty?
                    pc.lookup_keys << key
                  else
                    @import_errors += key.errors.map(&:to_s)
                  end
                end if changed_params["new"]
                # Unbind old parameters
                changed_params["obsolete"].each do |param_str, value|
                  key = pc.lookup_keys.find_by_key param_str
                  if key.nil?
                    @import_errors << "Unable to find puppet class #{pclass} smart-variable #{param_str} in the foreman database"
                  else
                    #pc.lookup_keys.delete key
                    key.puppetclass_id = nil
                    key.save!
                  end
                end if changed_params["obsolete"]
                # Update parameters (affects solely the default value)
                changed_params["updated"].each do |param_str, value|
                  key = pc.lookup_keys.find_by_key param_str
                  if key.errors.empty?
                    key.default_value = value
                    key.save!
                  else
                    @import_errors += key.errors.map(&:to_s)
                  end
                end if changed_params["updated"]
              end
              if attributes.has_key?("modeline")
                # Update modeline.
                pc.modeline = attributes["modeline"]
              end
              pc.save!
            else
              @import_errors += pc.errors.map(&:to_s)
            end
          end
        else
          @import_errors << "Unable to find or create environment #{env_str} in the foreman database"
        end
      end if changed[:updated]

      @import_errors
    end

    def find_import_proxies
      if (f = Feature.where(:name => "Puppet"))
        if !f.empty? and (proxies=f.first.smart_proxies)
          return proxies
        end
      end
      []
    end
  end

  def as_json(options={ })
    options ||= { }
    super({ :only => [:name, :id] }.merge(options))
  end

end

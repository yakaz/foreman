class LookupKey < ActiveRecord::Base
  include Authorization

  VALIDATION_TYPES = %w( string list regexp boolean integer real range array hash yaml json )

  TRUE_VALUES = [true, 1, '1', 't', 'T', 'true', 'TRUE', 'on', 'ON', 'yes', 'YES', 'y', 'Y'].to_set
  FALSE_VALUES = [false, 0, '0', 'f', 'F', 'false', 'FALSE', 'off', 'OFF', 'no', 'NO', 'n', 'N'].to_set

  KEY_DELM = ","
  EQ_DELM  = "="

  before_save :sanitize_path, :apply_default_value_stuff
  after_initialize :load_default_value_stuff

  serialize :default_value
  serialize :validator_rule

  belongs_to :puppetclass
  has_many :lookup_values, :dependent => :destroy, :inverse_of => :lookup_key
  accepts_nested_attributes_for :lookup_values, :reject_if => lambda { |a| a[:value].blank? }, :allow_destroy => true
  validates_uniqueness_of :key, :scope => :puppetclass_id, :if => Proc.new { |lookup_key| lookup_key.puppetclass && lookup_key.is_param } # unique parameter name per puppetclass
  validates_presence_of :key # unique global name (only for non detached smart-vars)
  validates_inclusion_of :validator_type, :in => VALIDATION_TYPES, :message => "invalid", :allow_blank => true, :allow_nil => true
  before_validation :validate_and_cast_rule
  before_validation :validate_and_cast_default_value
  validates_associated :lookup_values

  scoped_search :on => :key, :complete_value => true, :default_order => true
  scoped_search :in => :puppetclass, :on => :name, :rename => :puppetclass, :complete_value => true
  scoped_search :in => :lookup_values, :on => :value, :rename => :value, :complete_value => true

  default_scope :order => 'LOWER(lookup_keys.key)'
  scope :for, lambda { |c| where('lookup_keys.path LIKE ?', c) }

  attr_accessor :no_default_value

  private
  def load_default_value_stuff
    # Initialize our fake no_default_value attribute
    @no_default_value = read_attribute(:default_value).nil?
  end

  def apply_default_value_stuff
    # Enforce no_default_value (was deferred to permit order independent assigment to default_value and no_default_value)
    write_attribute(:default_value, nil) if @no_default_value
  end

  public
  def self.find_parameter puppetclass, parameter
    puppetclass = puppetclass.name if puppetclass.is_a? Puppetclass
    self.find_by_key "#{puppetclass}/#{parameter}"
  end

  def self.from_param param
    LookupKey.find(param.sub /-.*$/, '')
  end

  def to_param
    return id.to_s unless puppetclass # detached smart-vars have no unicity constraint
    "#{id}-#{puppetclass.name}$#{key}"
  end

  def to_s
    key
  end

  def clone
    new = super
    new.lookup_values = lookup_values.map(&:clone)
    new
  end

  # A nil return value is an error for mandatory lookup keys (no default value
  # and no triggered matcher) that should be properly handled by the caller.
  # For non mandatory lookup keys, it means that it should not be mentioned.
  # params:
  #   +host: The considered Host instance.
  #   +facts+: Cached facts hash, or nil.
  #   +options+: A hash containing the following, optional keys:
  #     +on_unavailable_fact+: Callback called upon unknown facts. See +substitute_facts+.
  #     +obs_matcher_block+: Callback to notify with extra information.
  #                          It is given a hash having the following structure:
  #                          +{ :host => #<Host>, :used_matched => "fact=value", :value => {:original => ..., :final => ...} }+
  #     +skip_fqdn+: Boolean value indicating whether to skip the fqdn matcher. Defaults to false.
  #                  Useful to give the previous value, prior to an eventual override.
  #TODO: use SQL coalesce to minimize the amount of queries
  def value_for host, facts = nil, options = {}
    on_unavailable_fact = options[:on_unavailable_fact]
    obs_matcher_block = options[:obs_matcher_block]
    skip_fqdn = options[:skip_fqdn] || false
    facts = host.facts_hash if facts == nil
    used_matcher = nil
    original_value = default_value
    path2matches(host).each do |match|
      if (v = lookup_values.find_by_match(match)) and not (skip_fqdn and match =~ /^fqdn=/)
        original_value = v.value
        used_matcher = match
        break
      end
    end
    v = substitute_facts original_value, host, facts, on_unavailable_fact
    obs_matcher_block.call({:host => host, :used_matcher => used_matcher, :value => {:original => original_value, :final => v}}) unless obs_matcher_block.nil?
    v
  end

  def default_value
    # Hide the current default_value if no_default_value is true
    # Note that setting this attribute works in order to permit
    # order independent affectation for default_value and no_default_value.
    read_attribute(:default_value) unless @no_default_value
  end

  def default_value_before_type_cast
    value_before_type_cast default_value
  end

  def value_before_type_cast value
    case validator_type.to_sym
    when :json
      value = JSON.dump value
    when :yaml, :array, :hash
      return 'null' if value.nil?
      value = YAML.dump value
      # Remove preceding "---" and indentation, for readability in the form
      value.sub! /\A---\s*$\n/, ''
      value.gsub! /^#{$1}/, '' if value =~ /\A( +)/
    end unless validator_type.blank?
    value
  end

  def no_default_value= value
    # Ensure booleanness
    @no_default_value = ActiveRecord::ConnectionAdapters::Column.value_to_boolean value
  end

  def path
    read_attribute(:path) || array2path(Setting["Default_variables_Lookup_Path"])
  end

  def path=(v)
    v = array2path v if v.is_a? Array
    return if v == array2path(Setting["Default_variables_Lookup_Path"])
    write_attribute(:path, v)
  end

  # Autodetects the best validator type for the given (correctly typed) value.
  # JSON and YAML are better undetected, to prevent the simplest strings to match.
  def self.suggest_validator_type value, default = nil, detect_json_or_yaml = false
    case value
    when String
      begin
        return "json" if JSON.load value
      rescue
        return "yaml" if YAML.load value
      end if detect_json_or_yaml
      "string"
    when Regexp
      "regexp"
    when Range
      "range"
    when TrueClass, FalseClass
      "boolean"
    when Integer
      "integer"
    when Float
      "real"
    when Set
      "list"
    when Array
      "array"
    when Hash
      "hash"
    else
      default
    end
  end

  def validator_rule_before_type_cast
    case validator_rule
    when Range
      start = validator_rule.begin
      mid = validator_rule.exclude_end? ? '...' : '..'
      stop = validator_rule.end
      start = "\"#{start}\"" if start.is_a? String
      stop = "\"#{stop}\"" if stop.is_a? String
      "#{start}#{mid}#{stop}"
    else
      validator_rule
    end
  end

  # Returns the casted value, or raises a TypeError
  def cast_validate_value value
    method = "cast_value_#{validator_type}".to_sym
    return value unless self.respond_to? method, true
    self.send(method, value) rescue raise TypeError
  end

  private

  # Generate possible lookup values type matches to a given host
  def path2matches host
    raise "Invalid Host" unless host.is_a?(Host)
    matches = []
    path_elements.each do |rule|
      match = []
      rule.each do |element|
        match << "#{element}#{EQ_DELM}#{attr_to_value(host,element)}"
      end
      matches << match.join(KEY_DELM)
    end
    matches
  end

  # translates an element such as domain to its real value per host
  # tries to find the host attribute first, parameters and then fallback to a puppet fact.
  def attr_to_value host, element
    # direct host attribute
    return host.send(element) if host.respond_to?(element)
    # host parameter
    return host.host_params[element] if host.host_params.include?(element)
    # fact attribute
    if (fn = host.fact_names.first(:conditions => { :name => element }))
      return FactValue.where(:host_id => host.id, :fact_name_id => fn.id).first.value
    end
  end

  def path_elements
    path.split.map do |paths|
      paths.split(KEY_DELM).map do |element|
        element
      end
    end
  end

  def sanitize_path
    self.path = path.tr("\s","").downcase unless path.blank?
  end

  def array2path array
    raise "invalid path" unless array.is_a?(Array)
    array.map do |sub_array|
      sub_array.is_a?(Array) ? sub_array.join(KEY_DELM) : sub_array
    end.join("\n")
  end

  def as_json(options={})
    super({:only => [:key, :is_param, :description, :default_value, :id]}.merge(options))
  end

  private

  def validate_and_cast_rule
    method = "cast_rule_#{validator_type}".to_sym
    unless self.respond_to? method, true
      # If there is no rule validation, then validator_rule is useless
      self.validator_rule = nil
    else
      begin
        self.validator_rule = self.send(method, self.validator_rule)
        true
      rescue
        errors.add(:validator_rule, "is invalid")
        return false
      end
    end
  end

  def validate_and_cast_default_value
    return true if default_value.nil?
    begin
      self.default_value = cast_validate_value self.default_value
      true
    rescue
      errors.add(:default_value, "is invalid")
      false
    end
  end

  def cast_rule_regexp rule
    rule = Regexp.new(validator_rule)
  end

  def cast_rule_range rule
    case rule
    when /^(\d+)(\.{2,3})(\d+)$/
      Range.new($1.to_i, $3.to_i, $2 == '...')
    when /^(['"])(.*?)\1(\.{2,3})(['"])(.*?)\4$/
      Range.new($2, $5, $3 == '...')
    else
      raise TypeError
    end
  end

  def cast_rule_list rule
    rule.split(KEY_DELM).map(&:strip)
  end

  def cast_value_range value
    value = value.to_i if validator_rule.begin.is_a? Integer
    raise TypeError unless validator_rule.include? value
    value
  end

  def cast_value_regexp value
    raise TypeError unless validator_rule === value
    value
  end

  def cast_value_boolean value
    return true if TRUE_VALUES.include? value
    return false if FALSE_VALUES.include? value
    raise TypeError
  end

  def cast_value_integer value
    return value.to_i if value.is_a?(Numeric)

    if value.is_a?(String)
      if value =~ /^0x[0-9a-f]+$/i
        value.to_i(16)
      elsif value =~ /^0[0-7]+$/
        value.to_i(8)
      elsif value =~ /^-?\d+$/
        value.to_i
      else
        raise TypeError
      end
    end
  end

  def cast_value_real value
    return value if value.is_a? Numeric
    if value.is_a?(String)
      if value =~ /^[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?$/
        value.to_f
      else
        cast_value_integer value
      end
    end
  end

  def cast_value_list value
    raise TypeError unless validator_rule.include? value
    value
  end

  def load_yaml_or_json value
    return value unless value.is_a? String
    begin
      JSON.load value
    rescue
      YAML.load value
    end
  end

  def cast_value_array value
    return value if value.is_a? Array
    return value.to_a if not value.is_a? String and value.is_a? Enumerable
    value = load_yaml_or_json value
    raise TypeError unless value.is_a? Array
    value
  end

  def cast_value_hash value
    return value if value.is_a? Hash
    value = load_yaml_or_json value
    raise TypeError unless value.is_a? Hash
    value
  end

  def cast_value_yaml value
    value = YAML.load value
  end

  def cast_value_json value
    value = JSON.load value
  end

  # params:
  #   +value+: The value to perform substitutions onto.
  #   +host+: The considered Host instance.
  #   +facts+: The cached facts hash, or nil.
  #   +on_unavailable_fact+: Called when facing an unknown fact.
  #                          It is given, in order: the fact name, the Host instance.
  #                          If not nil, the return value will be used for the missing value.
  def substitute_facts value, host, facts = nil, on_unavailable_fact = nil
    facts = host.facts_hash if facts.nil?
    case value
    when String
      value.gsub /\$\{([^\}]*)\}/ do |var|
        var = $1.sub /^::/, ''
        if facts.has_key?(var)
          facts[var]
        else
          (on_unavailable_fact.call(var, host).to_s if on_unavailable_fact) || ''
        end
      end
    when Array
      value.map { |v| substitute_facts v, host, facts, on_unavailable_fact }
    when Hash
      Hash[value.each.map { |k,v| [substitute_facts(k,host,facts,on_unavailable_fact), substitute_facts(v,host,facts,on_unavailable_fact)] }]
    else
      value
    end
  end

end

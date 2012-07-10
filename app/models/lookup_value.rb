class LookupValue < ActiveRecord::Base
  include Authorization
  belongs_to :lookup_key
  validates_uniqueness_of :match, :scope => :lookup_key_id
  validates_presence_of :match, :value
  delegate :key, :to => :lookup_key
  before_validation :sanitize_match
  before_validation :validate_and_cast_value
  validate :validate_match
  serialize :value

  scope :default, :conditions => { :match => "default" }, :limit => 1

  default_scope :order => 'LOWER(lookup_values.value)'

  scoped_search :on => :value, :complete_value => true, :default_order => true
  scoped_search :on => :match, :complete_value => true
  scoped_search :in => :lookup_key, :on => :key, :rename => :lookup_key, :complete_value => true

  def name
    value
  end

  def value_before_type_cast
    # Use the helper of our parent
    casted = self.value
    casted = lookup_key.value_before_type_cast casted unless lookup_key.nil?
    casted
  end

  private

  # TODO: ensures that the match contain only allowed path elements
  def validate_match
  end

  #TODO check multi match with matchers that have space (hostgroup = web servers,environment = production)
  def sanitize_match
    self.match = match.split(LookupKey::KEY_DELM).map {|s| s.split(LookupKey::EQ_DELM).map(&:strip).join(LookupKey::EQ_DELM)}.join(LookupKey::KEY_DELM) unless match.blank?
  end

  def validate_and_cast_value
    return true if self.marked_for_destruction?
    begin
      self.value = lookup_key.cast_validate_value self.value
      true
    rescue
      errors.add(:value, "is invalid")
      false
    end
  end

  def as_json(options={})
    super({:only => [:value, :match, :lookup_key_id, :id]}.merge(options))
  end

end

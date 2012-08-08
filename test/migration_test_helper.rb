ENV["RAILS_ENV"] = "test"
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'
require 'ap'

class ActiveRecord::MigrationTestCase < ActiveSupport::TestCase
  fixtures :users

  setup :be_admin
  setup :load_appropriate_migration

  def be_admin
    User.current = users(:admin)
  end

  def load_appropriate_migration
    pattern = "db/migrate/#{'[0-9]'*14}_#{self.class.name.underscore.chomp('_migration_test')}.rb"
    matches = Dir.glob(pattern)
    raise "No matching migration to load for \"#{pattern}\"" if matches.empty?
    raise "Multiple migration matching \"#{pattern}\"" if matches.size > 1
    require matches.first
    @migration = self.class.name.chomp('MigrationTest').constantize.new
  end

  def up
    if @migration.respond_to? :up_without_benchmarks
      @migration.up_without_benchmarks
    elsif @migration.class.respond_to? :up_without_benchmarks
      @migration.class.up_without_benchmarks
    else
      raise "No up method available in the migration object!"
    end
  end

  def down
    if @migration.respond_to? :down_without_benchmarks
      @migration.down_without_benchmarks
    elsif @migration.class.respond_to? :down_without_benchmarks
      @migration.class.down_without_benchmarks
    else
      raise "No down method available in the migration object!"
    end
  end
end

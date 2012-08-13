ENV["RAILS_ENV"] = "test"
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'
require 'ap'

class ActiveRecord::MigrationTestCase < ActiveSupport::TestCase

  def self.inherited(subclass)
    if subclass.load_appropriate_migration
      fixtures :users

      setup :be_admin
      setup :silence_migrations
      setup :get_migration_instance
    else
      class_eval do
        alias :run :skip_run
      end
    end
  end

  def self.load_appropriate_migration
    pattern = "db/migrate/#{'[0-9]'*14}_#{self.name.underscore.chomp('_migration_test')}.rb"
    matches = Dir.glob(pattern)
    raise "No matching migration to load for \"#{pattern}\"" if matches.empty?
    raise "Multiple migration matching \"#{pattern}\"" if matches.size > 1

    match = matches.first
    @@migration_version = match.sub(/^db\/migrate\/(#{'[0-9]'*14})_.*\.rb$/, '\1').to_i

    if ActiveRecord::Migrator.get_all_versions.include? @migration_version
      puts "Warning: Migration already applied: #{match}. Skipping its tests..."
      false
    else
      require match
      @@migration = self.name.chomp('MigrationTest').constantize
      true
    end
  end

  def skip_run *args, &block
    unless @method_name == "default_test"
      print "S"
      $stdout.flush
    end
  end

  def be_admin
    User.current = users(:admin)
  end

  def silence_migrations
    ActiveRecord::Migration.verbose = false
  end

  def get_migration_instance
    @migration = @@migration.new
  end

  def up
    # Work on the instance first
    if @migration.respond_to? :up_without_benchmarks
      @migration.up_without_benchmarks
    # Then try on the class
    elsif @migration.class.respond_to? :up_without_benchmarks
      @migration.class.up_without_benchmarks
    else
      raise "No up method available in the migration object!"
    end
  end

  def down
    # Work on the instance first
    if @migration.respond_to? :down_without_benchmarks
      @migration.down_without_benchmarks
    # Then try on the class
    elsif @migration.class.respond_to? :down_without_benchmarks
      @migration.class.down_without_benchmarks
    else
      raise "No down method available in the migration object!"
    end
  end

end

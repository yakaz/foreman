require 'migration_test_helper'

class PuppetclassesBelongToEnvironmentsMigrationTest < ActiveRecord::MigrationTestCase
  setup do
  end

  test "up does not fail" do
    up
  end

  test "up then down does not fail" do
    up
    down
  end

end

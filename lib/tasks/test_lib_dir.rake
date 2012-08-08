namespace :test do

  desc "Test lib source"
  Rake::TestTask.new(:lib) do |t|
    t.libs << "test"
    t.pattern = 'test/lib/**/*_test.rb'
    t.verbose = true
  end

  desc "Test migrations"
  Rake::TestTask.new(:migration) do |t|
    t.libs << "test"
    t.pattern = 'test/migration/**/*_test.rb'
    t.verbose = true
  end

end

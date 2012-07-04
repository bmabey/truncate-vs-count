# truncate-vs-count-on-mysql.rb
require 'logger'
require 'active_record'

require 'benchmark'
require 'sugar-high/dsl' # I just can't write this ActiveRecord::Base.connection each time!

ActiveRecord::Base.logger = Logger.new(STDERR)

puts "Active Record #{ActiveRecord::VERSION::STRING}"

ActiveRecord::Base.establish_connection(
  :adapter  => 'mysql2',
  :database => 'truncate_vs_count',
  :host => 'localhost',
  :username => 'root',
  :password => '',
  :encoding => 'utf8'
)

require 'database_cleaner'

DatabaseCleaner.strategy = :truncation

N = 30
Nrecords = 0

1.upto(30).each do |n|
  ActiveRecord::Schema.define do
    create_table :"users_#{n}", :force => true do |t|
      t.integer :name
    end
  end

  class_eval %{
    class ::User#{n} < ActiveRecord::Base
      self.table_name = 'users_#{n}'
    end
  } 
end

def fill_tables
  class_eval %{
    1.upto(N) do |n|
      1.upto(Nrecords) do |nr|
        User#{N}.create!
      end
    end
  }
end

truncation_with_counts_no_reset_ids = Benchmark.measure do
  with ActiveRecord::Base.connection do
    tables.each do |table|
      table_count = execute("SELECT COUNT(*) FROM #{table}").first.first
      if table_count == 0
        next
      else
        execute "TRUNCATE TABLE #{table}"
      end
    end
  end
end

fill_tables

truncation_with_counts = Benchmark.measure do
  with ActiveRecord::Base.connection do
    tables.each do |table|
      table_count = execute("SELECT COUNT(*) FROM #{table}").first.first
      if table_count == 0
        # if we set 'next' right here
        # it will work EVEN MORE FAST (10ms for 30 tables)!
        # But problem that then we will not reset AUTO_INCREMENT
        #
        # 
        # next

        auto_inc = execute <<-AUTO_INCREMENT
          SELECT Auto_increment 
          FROM information_schema.tables 
          WHERE table_name='#{table}'
        AUTO_INCREMENT

        execute "TRUNCATE TABLE #{table}" if auto_inc.first.first > 1

        # This is slower than just TRUNCATE
        # execute "ALTER TABLE #{table} AUTO_INCREMENT = 1" if auto_inc.first.first > 1
      else
        execute "TRUNCATE TABLE #{table}"
      end
    end
  end
end

fill_tables

just_truncation = Benchmark.measure do
  with ActiveRecord::Base.connection do
    tables.each do |table|
      execute "TRUNCATE TABLE #{table}"
    end
  end
end

fill_tables

database_cleaner = Benchmark.measure do
  DatabaseCleaner.clean
end

puts "Truncate non-empty tables (AUTO_INCREMENT is not ensured)\n#{truncation_with_counts_no_reset_ids}"

puts "Truncate non-empty tables (AUTO_INCREMENT ensured)\n#{truncation_with_counts}"

puts "Truncate all tables one by one:\n#{just_truncation}"

puts "Truncate all tables with DatabaseCleaner:\n#{database_cleaner}"

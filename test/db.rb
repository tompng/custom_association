require 'benchmark'
require 'active_record'

class User < ActiveRecord::Base
  has_many :posts
end

class Post < ActiveRecord::Base
  belongs_to :user
  has_many :comments
end

class Comment < ActiveRecord::Base
  belongs_to :user
  belongs_to :post
end

module DB
  DATABASE_CONFIG = {
    adapter: 'sqlite3',
    database: ENV['DATABASE_NAME'] || 'test/development.sqlite3',
    pool: 5,
    timeout: 5000
  }
  ActiveRecord::Base.establish_connection DATABASE_CONFIG
  ActiveRecord::Base.logger = Logger.new(STDOUT)

  def self.migrate
    File.unlink DATABASE_CONFIG[:database] if File.exist? DATABASE_CONFIG[:database]
    ActiveRecord::Base.clear_all_connections!
    ActiveRecord::Migration::Current.class_eval do
      create_table :users do |t|
        t.string :name
        t.timestamps
      end
      create_table :posts do |t|
        t.string :title
        t.string :body
        t.references :user, index: true
        t.timestamps
      end
      create_table :comments do |t|
        t.string :body
        t.references :user, index: true
        t.references :post, index: true
        t.timestamps
      end
    end
  end

  def self.seed
    users = Array.new(8) { |i| User.create name: "User#{i}" }
    authors = users.sample(4)
    posts = 16.times.flat_map do |i|
      authors.sample.posts.create title: "title#{i}", body: "body#{i}"
    end
    hotentries = posts.sample(8)
    32.times.flat_map do |i|
      hotentries.sample.comments.create user: users.sample, body: "comment#{i}"
    end
  end
end

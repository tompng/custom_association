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
  has_many :emotions
end

class Emotion < ActiveRecord::Base
  belongs_to :comment
  belongs_to :user
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
      create_table :emotions do |t|
        t.string :kind
        t.references :user, index: true
        t.references :comment, index: true
        t.timestamps
      end
      add_index :emotions, [:comment_id, :user_id], unique: true
    end
  end

  def self.seed
    users = Array.new(8) { |i| User.create name: "User#{i}" }
    authors = users.sample 4
    posts = 16.times.flat_map do |i|
      authors.sample.posts.create title: "title#{i}", body: "body#{i}"
    end
    hotentries = posts.sample 8
    32.times.flat_map do |i|
      comment = hotentries.sample.comments.create user: users.sample, body: "comment#{i}"
      users.sample(rand(0..8)).each do |user|
        comment.emotions.create user: user, kind: %w(happy sad angry).sample
      end
    end
  end
end

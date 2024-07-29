require "test_helper"
require 'db'

DB.migrate
DB.seed

module QueryHook
  module Interceptor
    # activerecord <= 7.0
    def exec_query(*args, **option)
      QueryHook.query_executed args
      super
    end

    # activerecord >= 7.1
    def internal_exec_query(*args, **option)
      QueryHook.query_executed args
      super
    end
  end

  def self.query_executed query
    @queries&.push(query)
  end

  def self.count_query
    @queries = []
    yield
    @queries.size
  ensure
    @queries = nil
  end

  ActiveRecord::Base.connection.singleton_class.prepend Interceptor
end

class User
  has_custom_association :posts_at_idx3, mapper: ->(preloaded) { preloaded[id]&.[] 3 } do |users|
    Post.where(user_id: users.map(&:id)).group_by(&:user_id)
  end
  has_custom_association :odd_posts, default: [] do |users|
    Post.where(user_id: users.map(&:id)).where('id % 2 = 1').group_by(&:user_id)
  end
end

class Post
  has_custom_association :comments_count, default: 0 do |posts|
    Post.where(id: posts.map(&:id)).joins(:comments).group(:id).count
  end
  has_custom_association :author, mapper: :user_id do |posts|
    User.where(id: posts.map(&:user_id).uniq).index_by(&:id)
  end
end

class Comment
  has_custom_association :emotion_summary, default: {} do |comments|
    emotions = Emotion.where comment_id: comments.map(&:id)
    counts = emotions.group(:comment_id, :kind).count
    grouped_counts = counts.group_by { |(id, _kind), _count| id }
    grouped_counts.transform_values do |id_kind_counts|
      id_kind_counts.map { |(_id, kind), count| [kind, count] }.to_h
    end
  end
end

class CustomAssociationTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::CustomAssociation::VERSION
  end

  def test_custom_through_custom
    to_hash = ->(users) { users.map { |u| u.posts_at_idx3&.comments_count } }
    answer = User.all.map { |u| u.posts[3]&.comments&.count }
    includes = { posts_at_idx3: :comments_count }
    assert_equal answer, to_hash.call(User.all)
    assert_equal answer, to_hash.call(User.all.includes(includes))
    assert_equal answer, to_hash.call(User.all.preload(includes))
  end

  def test_symbol_mapper
    posts = Post.limit(4)
    authors = nil
    query_count = QueryHook.count_query do
      authors = posts.includes(:author).map(&:author)
    end
    assert_equal 2, query_count
    assert_equal posts.map(&:user), authors
  end

  def test_custom_normal_mixed
    tohash = lambda do |users|
      users.map do |u|
        [
          u.odd_posts.map { |c| c.comments.map(&:id) },
          u.posts.map(&:comments_count)
        ]
      end
    end
    answer = User.all.map do |u|
      [
        u.posts.select { |p| p.id.odd? }.map { |c| c.comments.map(&:id) },
        u.posts.map(&:comments).map(&:count)
      ]
    end
    includes = { odd_posts: :comments, posts: :comments_count }
    assert_equal answer, tohash.call(User.all)
    assert_equal answer, tohash.call(User.all.includes(includes))
    assert_equal answer, tohash.call(User.all.preload(includes))
  end

  def test_emotions
    comments = Comment.limit(8)
    sqlcounts = QueryHook.count_query { comments.includes(:emotion_summary).map(&:emotion_summary) }
    assert_equal 2, sqlcounts
    summary = comments.map(&:emotion_summary)
    correct_summary = comments.map { |c| c.emotions.group(:kind).count }
    assert_equal correct_summary, summary
  end

  def test_assert_query_reduced
    tohash = lambda do |users|
      users.map(&:posts_at_idx3).compact.map(&:comments_count)
      users.flat_map(&:odd_posts).flat_map(&:comments).map(&:id)
    end
    includes = { posts_at_idx3: :comments_count, odd_posts: :comments }
    querybefore = QueryHook.count_query { tohash.call User.all }
    queryincludes = QueryHook.count_query { tohash.call User.all.includes(includes) }
    querypreload = QueryHook.count_query { tohash.call User.all.preload(includes) }
    queryafter = QueryHook.count_query { tohash.call User.all }
    assert_equal 5, queryincludes
    assert_equal 5, querypreload
    assert_equal querybefore, queryafter
    assert querybefore > 10
  end

  def test_join_error
    assert User.preload(:odd_posts).to_a

    assert_raises CustomAssociation::EagerLoadError do
      User.joins(:odd_posts).to_a
    end

    assert_raises CustomAssociation::EagerLoadError do
      User.eager_load(:odd_posts).to_a
    end
  end
end

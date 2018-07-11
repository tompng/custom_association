# CustomAssociation

Define custom association for eager loading

```ruby
gem 'custom_association', github: 'tompng/custom_association'
```

## How to use

```ruby
# define your custom association and preloading logic
class User < ActiveRecord::Base
  has_many :posts
  has_custom_association :foo do |users|
    # preload all foos associated to users
    return { user1.id => foo1, user2.id => foo2, ... }
  end
  has_custom_association :bar, mapper: :bar_id do |users|
    # preload all bars associated to users
    return { user1.bar_id => bar1, user2.bar_id => bar2, ... }
  end
  has_custom_association :baz, mapper: ->(result) { result.retrieve_baz_for user: self } do |users|
    # preload all bazs associated to users
    # return any preload result you want to pass to mapper
  end
end
User.includes(:posts, :foo, bar: :user, baz: :comments)
User.preload(:posts, :foo, bar: :user, baz: :comments)
# User.eager_load(:posts, :foo, bar: :user, baz: :comments) <- cannot join
```

## Practical Examples

```ruby
# reduce N+1 `user.posts.last` queries
class User < ActiveRecord::Base
  has_custom_association :last_post do |users|
    Post.where(user_id: users.map(&:id)).select('max(id), *').group(:user_id).index_by(&:user_id)
  end
end

class Post < ActiveRecord::Base
  belongs_to :user
  has_many :comments

  # reduce N+1 `comments.count` queries
  has_custom_association :comments_count, default: 0, do |posts|
    Post.where(id: posts.map(&:id)).joins(:comments).group(:id).count
  end

  # reduce N+1 `comments.limit(5)` queries
  has_custom_association :last_five_comments, default: [], do |posts|
    sql = 'nice and sweet sql to get last five comments for each post'
    Comment.where(post_id: posts.map(&:id)).where(sql).group_by(&:post_id)
    # this can be done with the below code using 'tompng/top_n_loader'
    # TopNLoader.load_associations(Post, posts.map(&:id), :comments, limit: 5, order: { id: :desc })
  end
end

# reduce N+1 `group(:kind).count` queries
class Comment < ActiveRecord::Base
  has_many :emotions
  has_custom_association :emotion_summary, default: {} do |comments|
    emotions = Emotion.where comment_id: comments.map(&:id)
    counts = emotions.group(:comment_id, :kind).count
    grouped_counts = counts.group_by { |(id, _kind), _count| id }
    grouped_counts.transform_values do |id_kind_counts|
      id_kind_counts.map { |(_id, kind), count| [kind, count] }.to_h
    end
  end
end

# reduce N+1 api calls
class User < ActiveRecord::Base
  has_custom_association :icon, do |users|
    urls = SomeWebApi.batch_get_icon_urls(users.map(&:some_web_api_user_id))
    users.map(&:id).zip(urls).to_h
  end
  has_custom_association :redisvalue, do |users|
    values = redis_client.mget(*users.map { |u| "prefix#{u.id}" })
    users.map(&:id).zip(values).to_h
  end
end
```

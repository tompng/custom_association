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
  has_custom_association :foo, preloader: ->(users) {
    preload all foos associated to users
    return { user_id1 => foo1, user_id2 => foo2, ... }
  }
  has_custom_association :bar, preloader: ->(users) {
    preload all bars associated to users
    return temporary_result
  } do |temporary_result|
    temporary_result.retrieve_bar_for(user_id: self.id)
  end
end
User.includes(:posts, :foo, bar: :comments)
User.preload(:posts, :foo, bar: :comments)
# User.eager_load(:posts, :foo, bar: :comments) <- cannot join
```

## Practical Examples
```ruby
# reduce N+1 `user.posts.last` queries
class User < ActiveRecord::Base
  has_custom_association :last_post, preloader: ->(users) {
    Post.where(user_id: users.map(&:id)).select('max(id), *').group(:user_id).index_by(&:user_id)
  }
end

class Post < ActiveRecord::Base
  belongs_to :user
  has_many :comments

  # reduce N+1 `comments.count` queries
  has_custom_association :comments_count, preloader: ->(posts) {
    Hash.new(0).merge Post.where(id: posts.map(&:id)).joins(:comments).group(:id).count
  }

  # reduce N+1 `comments.limit(5)` queries
  has_custom_association :last_five_comments, preloader: ->(posts) {
    sql = 'nice and sweet sql to get last five comments for each post'
    Hash.new{[]}.merge Comment.where(post_id: posts.map(&:id)).where(sql).group_by(&:post_id)
    # this can be done with the below code using 'topng/top_n_loader'
    # TopNLoader.load_associations(Post, posts.map(&:id), :comments, limit: 5, order: { id: :desc })
  }
end

# reduce N+1 `group(:kind).count` queries
class Comment < ActiveRecord::Base
  has_many :emotions
  has_custom_association :emotion_summary, preloader: ->(comments) {
    emotions = Emotion.where comment_id: comments.map(&:id)
    counts = emotions.group(:comment_id, :kind).count
    grouped_counts = counts.group_by { |(id, _kind), _count| id }
    result = grouped_counts.transform_values do |id_kind_counts|
      id_kind_counts.map { |(_id, kind), count| [kind, count] }.to_h
    end
    Hash.new { {} }.merge result
  }
end

# reduce N+1 api calls
class User < ActiveRecord::Base
  has_custom_association :icon, preloader: ->(users) {
    urls = SomeWebApi.batch_get_icon_urls(users.map(&:some_web_api_user_id))
    users.map(&:id).zip(urls).to_h
  }
  has_custom_association :redisvalue, preloader: ->(users) {
    values = redis_client.mget(*users.map { |u| "prefix#{u.id}" })
    users.map(&:id).zip(values).to_h
  }
end
```

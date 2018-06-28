User.has_custom_association :foobar, preloader: ->us{Post.where(user_id: us.map(&:id)).index_by(&:user_id)}
User.has_custom_association :foobars, preloader: ->us{Hash.new{[]}.update Post.where(user_id: us.map(&:id)).group_by(&:user_id)}
User.preload(foobar: :comments).map { |u| u.foobar&.comments }

def (ActiveRecord::Base).has_count_of(name)
  has_custom_association "#{name}_count", preloader: ->(records) {
    counts = Hash.new(0)
    records.group_by(&:class).each do |klass, klass_records|
      counts.update klass.where(id: klass_records.map(&:id)).joins(name).group(:id).count
    end
    counts
  }
end
Post.has_count_of :comments
User.preload(foobar: :comments_count).map { |u| u.foobar&.comments_count }
User.preload(foobars: :comments_count).map { |u| u.foobars.map(&:comments_count) }

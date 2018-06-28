class CustomAssociationLoader
  attr_reader :preloaded_records
  def initialize(klass, records, reflection, scope)
    @reflection = reflection
    @klass = klass
    @records = records
    @scope = scope
  end

  def run(_preloader)
    preloaded = @reflection.preloader.call @records
    @preloaded_records = @records.flat_map do |record|
      value = record.instance_exec preloaded, &@reflection.block
      record.association(@reflection.name).writer(value)
      value
    end
  end
end

module CustomPreloaderExtension
  def preloader_for(reflection, owners, rhs_klass)
    preloader = super
    return preloader if preloader
    return CustomAssociationLoader if reflection.macro == :has_custom_field
  end
end

class CustomAssociation < ActiveRecord::Associations::Association
  def macro
    :has_custom_field
  end

  def writer value
    @loaded = true
    @value = value
  end

  def reader
    return @value if @loaded
    writer load
  end

  def load
    preloaded = @reflection.preloader.call [@owner]
    @owner.instance_exec preloaded, &@reflection.block
  end
end

class CustomReflection < ActiveRecord::Reflection::AbstractReflection
  attr_reader :klass, :name, :preloader, :block
  def initialize(klass, name, preloader, block)
    @klass = klass
    @name = name
    @preloader = preloader
    @block = block || ->(preloaded) { preloaded[id] }
  end

  def macro
    :has_custom_field
  end

  def association_class
    CustomAssociation
  end

  def check_validity!; end

  def check_preloadable!; end
end

class << ActiveRecord::Base
  def has_custom_association(name, preloader:, &block)
    name = name.to_sym
    reflection = CustomReflection.new self, name, preloader, block
    ActiveRecord::Reflection.add_reflection self, name, reflection
    ActiveRecord::Associations::Builder::Association.define_readers(self, name)
  end
end

ActiveRecord::Associations::Preloader.prepend CustomPreloaderExtension

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

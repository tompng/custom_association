require 'active_record'
require 'custom_association/version'

class CustomAssociation::Preloader < ActiveRecord::Associations::Preloader::Association
  def loader_query
    self # load_records_in_batch is called
  end

  def load_records_in_batch(similar_loaders)
    similar_loaders.each(&:run)
  end

  def run
    return self if @run

    @run = true
    preloaded = @reflection.preloader.call @owners
    @preloaded_records = @owners.flat_map do |record|
      value = record.instance_exec preloaded, &@reflection.mapper
      record.association(@reflection.name).writer(value)
      value
    end.uniq.compact
    self
  end
end

module CustomAssociation::PreloaderExtension

    # def preloader_for(reflection, owners, rhs_klass)
    #   preloader = super
    #   return preloader if preloader
    #   return CustomAssociation::Preloader if reflection.macro == :has_custom_field
    # end

    # def preloader_for(reflection, owners)
    #   return CustomAssociation::Preloader if reflection.macro == :has_custom_field
    #   super
    # end
  def preloader_for(reflection)
    reflection.macro == :has_custom_field ? CustomAssociation::Preloader : super
  end
end

class CustomAssociation::Association < ActiveRecord::Associations::Association

  def macro
    :has_custom_field
  end

  def writer value
    @loaded = true
    @value = value.nil? ? @reflection.default : value
  end

  def reader
    load unless @loaded
    @value
  end

  def load
    preloaded = @reflection.preloader.call [@owner]
    writer @owner.instance_exec preloaded, &@reflection.mapper
  end
end

class CustomAssociation::EagerLoadError < StandardError; end

class CustomAssociation::Reflection < ActiveRecord::Reflection::AssociationReflection
  attr_reader :preloader, :mapper, :default

  def initialize(klass, name, preloader:, mapper:, default:)
    @klass = klass
    @name = name
    @preloader = preloader
    @mapper = mapper.is_a?(Symbol) ? ->(preloaded) { preloaded[send(mapper)] } : mapper
    @default = default
    @options = {} # HACK: AssociationReflection requires this.
  end

  def macro
    :has_custom_field
  end

  def check_validity!
  end

  def association_class
    CustomAssociation::Association
  end

  def check_eager_loadable!
    raise CustomAssociation::EagerLoadError, <<~MSG
      The association scope '#{name}' does not support join.
      Use `preload` instead of `eager_load`.
    MSG
  end
end

class << ActiveRecord::Base
  def has_custom_association(name, mapper: :id, default: nil, &block)
    name = name.to_sym
    reflection = CustomAssociation::Reflection.new self, name, preloader: block, mapper: mapper, default: default
    ActiveRecord::Reflection.add_reflection self, name, reflection
    ActiveRecord::Associations::Builder::Association.send(:define_readers, self, name)
  end
end

ActiveRecord::Associations::Preloader::Branch.prepend CustomAssociation::PreloaderExtension

module Neo4j::ActiveNode
  module Property
    extend ActiveSupport::Concern

    include ActiveAttr::Attributes
    include ActiveAttr::MassAssignment
    include ActiveAttr::TypecastedAttributes
    include ActiveAttr::AttributeDefaults
    include ActiveAttr::QueryAttributes
    include ActiveModel::Dirty

    class UndefinedPropertyError < RuntimeError; end
    class MultiparameterAssignmentError < StandardError; end

    def initialize(attributes={}, options={})
      attributes = process_attributes(attributes)
      relationship_props = self.class.extract_relationship_attributes!(attributes)
      writer_method_props = extract_writer_methods!(attributes)
      validate_attributes!(attributes)
      writer_method_props.each do |key, value|
        self.send("#{key}=", value)
      end

      super(attributes, options)
    end

    # Returning nil when we get ActiveAttr::UnknownAttributeError from ActiveAttr
    def read_attribute(name)
      super(name)
    rescue ActiveAttr::UnknownAttributeError
      nil
    end
    alias_method :[], :read_attribute

    def default_properties=(properties)
      keys = self.class.default_properties.keys
      @default_properties = properties.reject{|key| !keys.include?(key)}
    end

    def default_property(key)
      keys = self.class.default_properties.keys
      keys.include?(key.to_sym) ? default_properties[key.to_sym] : nil
    end

    def default_properties
      @default_properties ||= {}
      # keys = self.class.default_properties.keys
      # _persisted_node.props.reject{|key| !keys.include?(key)}
    end


    private

    # Changes attributes hash to remove relationship keys
    # Raises an error if there are any keys left which haven't been defined as properties on the model
    def validate_attributes!(attributes)
      invalid_properties = attributes.keys.map(&:to_s) - self.attributes.keys
      raise UndefinedPropertyError, "Undefined properties: #{invalid_properties.join(',')}" if invalid_properties.size > 0
    end

    def extract_writer_methods!(attributes)
      attributes.keys.inject({}) do |writer_method_props, key|
        writer_method_props[key] = attributes.delete(key) if self.respond_to?("#{key}=")

        writer_method_props
      end
    end

    # Gives support for Rails date_select, datetime_select, time_select helpers.
    def process_attributes(attributes = nil)
      multi_parameter_attributes = {}
      new_attributes = {}
      attributes.each_pair do |key, value|
        if key =~ /\A([^\(]+)\((\d+)([if])\)$/
          found_key, index = $1, $2.to_i
          (multi_parameter_attributes[found_key] ||= {})[index] = value.empty? ? nil : value.send("to_#{$3}")
        else
          new_attributes[key] = value
        end
      end

      multi_parameter_attributes.empty? ? new_attributes : process_multiparameter_attributes(multi_parameter_attributes, new_attributes)
    end

    def process_multiparameter_attributes(multi_parameter_attributes, new_attributes)
      multi_parameter_attributes.each_pair do |key, values|
        begin
          values = (values.keys.min..values.keys.max).map { |i| values[i] }
          field = self.class.attributes[key.to_sym]
          new_attributes[key] = instantiate_object(field, values)
        rescue => e
          raise MultiparameterAssignmentError, "error on assignment #{values.inspect} to #{key}"
        end
      end
      new_attributes
    end

    def instantiate_object(field, values_with_empty_parameters)
      return nil if values_with_empty_parameters.all? { |v| v.nil? }
      values = values_with_empty_parameters.collect { |v| v.nil? ? 1 : v }
      klass = field[:type]
      if klass
        klass.new(*values)
      else
        values
      end
    end

    module ClassMethods

      # Defines a property on the class
      #
      # See active_attr gem for allowed options, e.g which type
      # Notice, in Neo4j you don't have to declare properties before using them, see the neo4j-core api.
      #
      # @example Without type
      #    class Person
      #      # declare a property which can have any value
      #      property :name
      #    end
      #
      # @example With type and a default value
      #    class Person
      #      # declare a property which can have any value
      #      property :score, type: Integer, default: 0
      #    end
      #
      # @example With an index
      #    class Person
      #      # declare a property which can have any value
      #      property :name, index: :exact
      #    end
      #
      # @example With a constraint
      #    class Person
      #      # declare a property which can have any value
      #      property :name, constraint: :unique
      #    end
      def property(name, options={})
        magic_properties(name, options)
        attribute(name, options)

        # either constraint or index, do not set both
        if options[:constraint]
          raise "unknown constraint type #{options[:constraint]}, only :unique supported" if options[:constraint] != :unique
          constraint(name, type: :unique)
        elsif options[:index]
          raise "unknown index type #{options[:index]}, only :exact supported" if options[:index] != :exact
          index(name, options) if options[:index] == :exact
        end
      end

      def default_property(name, &block)
        default_properties[name] = block
      end

      # @return [Hash<Symbol,Proc>]
      def default_properties
        @default_property ||= {}
      end

      def default_property_values(instance)
        default_properties.inject({}) do |result,pair|
          result.tap{|obj| obj[pair[0]] = pair[1].call(instance)}
        end
      end

      def attribute!(name, options={})
        super(name, options)
        define_method("#{name}=") do |value|
          typecast_value = typecast_attribute(typecaster_for(self.class._attribute_type(name)), value)
          send("#{name}_will_change!") unless typecast_value == read_attribute(name)
          super(value)
        end
      end

      # Extracts keys from attributes hash which are relationships of the model
      # TODO: Validate separately that relationships are getting the right values?  Perhaps also store the values and persist relationships on save?
      def extract_relationship_attributes!(attributes)
        attributes.keys.inject({}) do |relationship_props, key|
          relationship_props[key] = attributes.delete(key) if self.has_relationship?(key)

          relationship_props
        end
      end

      private

      # Tweaks properties
      def magic_properties(name, options)
        set_stamp_type(name, options)
        set_time_as_datetime(options)
      end

      def set_stamp_type(name, options)
        options[:type] = DateTime if (name.to_sym == :created_at || name.to_sym == :updated_at)
      end

      # ActiveAttr does not handle "Time", Rails and Neo4j.rb 2.3 did
      # Convert it to DateTime in the interest of consistency
      def set_time_as_datetime(options)
        options[:type] = DateTime if options[:type] == Time
      end

    end
  end

end

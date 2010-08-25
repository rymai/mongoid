# encoding: utf-8
module Mongoid #:nodoc:
  module MultiParameterAttributes
    module Errors
      # Raised when an error occurred while doing a mass assignment to an attribute through the
      # <tt>attributes=</tt> method. The exception has an +attribute+ property that is the name of the
      # offending attribute.
      class AttributeAssignmentError < Mongoid::Errors::MongoidError
        attr_reader :exception, :attribute
        def initialize(message, exception, attribute)
          @exception = exception
          @attribute = attribute
          @message = message
        end
      end
      
      # Raised when there are multiple errors while doing a mass assignment through the +attributes+
      # method. The exception has an +errors+ property that contains an array of AttributeAssignmentError
      # objects, each corresponding to the error while assigning to an attribute.
      class MultiparameterAssignmentErrors < Mongoid::Errors::MongoidError
        attr_reader :errors
        def initialize(errors)
          @errors = errors
        end
      end
    end
    
    def process(attrs = nil)
      if attrs
        attributes = {}
        multi_parameter_attributes = []
        
        attrs.stringify_keys.each do |k, v|
          if k.include?("(")
            multi_parameter_attributes << [ k, v ]
          else
            attributes[k] = v
          end
        end
        super attributes.merge(assign_multiparameter_attributes(multi_parameter_attributes))
      else
        super
      end
    end
    
  protected
    
    def assign_multiparameter_attributes(pairs)
      execute_callstack_for_multiparameter_attributes(
        extract_callstack_for_multiparameter_attributes(pairs)
      )
    end
    
    def execute_callstack_for_multiparameter_attributes(callstack)
      attributes = {}
      errors = []
      callstack.each do |name, values_with_empty_parameters|
        begin
          klass = self.class.fields[name].try(:type)
          # in order to allow a date to be set without a year, we must keep the empty values.
          # Otherwise, we wouldn't be able to distinguish it from a date with an empty day.
          values = values_with_empty_parameters.reject { |v| v.nil? }
          
          if values.empty?
            attributes[name] = nil
          else
            
            value = if Time == klass
              instantiate_time_object(values)
            elsif Date == klass
              begin
                values = values_with_empty_parameters.collect { |v| v.nil? ? 1 : v }
                Date.new(*values)
              rescue ArgumentError => ex # if Date.new raises an exception on an invalid date
                instantiate_time_object(name, values).to_date # we instantiate Time object and convert it back to a date thus using Time's logic in handling invalid dates
              end
            else
              klass.new(*values)
            end
            
            attributes[name] = value
          end
        rescue => ex
          errors << Errors::AttributeAssignmentError.new("error on assignment #{values.inspect} to #{name}", ex, name)
        end
      end
      unless errors.empty?
        raise Errors::MultiparameterAssignmentErrors.new(errors), "#{errors.size} error(s) on assignment of multiparameter attributes"
      end
      attributes
    end
    
    def extract_callstack_for_multiparameter_attributes(pairs)
      attributes = { }
      
      for pair in pairs
        multiparameter_name, value = pair
        attribute_name = multiparameter_name.split("(").first
        attributes[attribute_name] = [] unless attributes.include?(attribute_name)
        
        parameter_value = value.empty? ? nil : type_cast_attribute_value(multiparameter_name, value)
        attributes[attribute_name] << [ find_parameter_position(multiparameter_name), parameter_value ]
      end
      
      attributes.each { |name, values| attributes[name] = values.sort_by{ |v| v.first }.collect { |v| v.last } }
    end
    
    def instantiate_time_object(values)
      (Time.zone or Time).send(Mongoid::Config.instance.use_utc? ? :utc : :local, *values)
    end
    
    def type_cast_attribute_value(multiparameter_name, value)
      multiparameter_name =~ /\([0-9]*([if])\)/ ? value.send("to_" + $1) : value
    end
    
    def find_parameter_position(multiparameter_name)
      multiparameter_name.scan(/\(([0-9]*).*\)/).first.first
    end
    
  end
end
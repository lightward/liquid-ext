# frozen_string_literal: true

module LightwardLiquidExt
  module Filters
    # push and unshift return a new array; the original is never changed.
    module ArrayFilters
      def push(object, *args)
        ArrayFilters.copy_of_array("push", object).push(*args)
      end

      def unshift(object, *args)
        ArrayFilters.copy_of_array("unshift", object).unshift(*args)
      end

      def self.copy_of_array(filter_name, object)
        unless object.respond_to?(:to_ary)
          raise(
            ArgumentError,
            "#{filter_name} can only be used on array-like objects; received #{Support.type_name(object)} instead",
          )
        end

        # to_ary returns the array itself when given an array, so copy it.
        object.to_ary.dup
      end
    end
  end
end

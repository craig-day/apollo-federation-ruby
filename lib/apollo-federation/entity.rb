# frozen_string_literal: true

require 'graphql'

module ApolloFederation
  class Entity < GraphQL::Schema::Union
    graphql_name '_Entity'

    def self.resolve_type(object, context)
      reference_type = context[:resolved_references][object]

      # If an entity interface was resolved, we need to resolve it to an actual type
      if reference_type.is_a?(Module) && reference_type.include?(GraphQL::Schema::Interface)
        resolve_type_results = context.schema.resolve_type(reference_type, object, context)

        if resolve_type_results.is_a?(Array) && resolve_type_results.size == 2
          # TODO: In GraphQL::Schema, when resolve_type returns a tuple, the object contained in the
          # tuple is used. Should we also do that, or do we want to stick with using object as-is?
          resolve_type_results.first
        else
          resolve_type_results
        end
      else
        reference_type
      end
    end
  end
end

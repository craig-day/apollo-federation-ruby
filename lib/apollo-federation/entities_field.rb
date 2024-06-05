# frozen_string_literal: true

require 'graphql'
require 'apollo-federation/any'

module ApolloFederation
  module EntitiesField
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      extend GraphQL::Schema::Member::HasFields

      def define_entities_field(possible_entities)
        # If there are any "entities", define the Entity union and and the Query._entities field
        return if possible_entities.empty?

        entity_type = Class.new(Entity) do
          possible_types(*possible_entities)
        end

        field(:_entities, [entity_type, null: true], null: false) do
          argument :representations, [Any], required: true
        end
      end
    end

    def _entities(representations:)
      final_result = Array.new(representations.size)
      grouped_references_with_indices =
        representations
        .map
        .with_index { |r, i| [r, i] }
        .group_by { |(r, _i)| r[:__typename] }

      maybe_lazies = grouped_references_with_indices.map do |typename, references_with_indices|
        references = references_with_indices.map(&:first)
        indices = references_with_indices.map(&:last)

        # TODO: Use warden or schema?
        type = context.warden.get_type(typename)
        unless valid_entity_type?(type)
          # TODO: Raise a specific error class?
          raise "The _entities resolver tried to load an entity for type \"#{typename}\"," \
                ' but no object type of that name was found in the schema'
        end

        type_class = class_of_type(type)

        if type_class.underscore_reference_keys
          references.map! do |reference|
            reference.transform_keys do |key|
              GraphQL::Schema::Member::BuildType.underscore(key.to_s).to_sym
            end
          end
        end

        # TODO: should we check a type to see if it implements an interface and then check that interface
        # for resolve_reference(s)?
        results =
          if type_class.respond_to?(:resolve_references)
            type_class.resolve_references(references, context)
          elsif type_class.respond_to?(:resolve_reference)
            references.map { |reference| type_class.resolve_reference(reference, context) }
          elsif type_class.include?(ApolloFederation::Interface)
            # An interface entity must define resolve_reference(s) to support the @interfaceObject
            # pattern where a reference is the interface name itself, not an implementing type
            raise "The _entities resolver was asked to resolve type '#{typename}', which is an entity" \
                  ' interface, but the interface did not define `resolve_references`'
          else
            references
          end

        context.schema.after_lazy(results) do |resolved_results|
          # If we get more results than asked for, the zip below will result in nil problems.
          # We could alternatively flip the zip and base it on indices and then ignore "extra" results.
          if resolved_results.size != indices.size
            raise "The entities resolver for type '#{typename}' returned wrong number of results:" \
                  " expected #{indices.size}, received #{resolved_results.size}"
          end

          resolved_results.zip(indices).each do |result, i|
            final_result[i] = context.schema.after_lazy(result) do |resolved_value|
              # Need to explicitly trigger type resolution of an entity interface, because normal
              # resolution will never return an interface as the type
              if type_class.include?(ApolloFederation::Interface)
                # type = context.schema.resolve_type(type, resolved_value, context)
                resolved_type_result = context.schema.resolve_type(type, resolved_value, context)

                # TODO: In GraphQL::Schema, the processing of this call will prefer the value returned
                # in the tuple. Should we also do that, or do we want to stick with using resolved_value as-is?
                type =
                  if resolved_type_result.is_a?(Array) && resolved_type_result.size == 2
                    resolved_type_result.first
                  else
                    resolved_type_result
                  end
              end

              # TODO: This isn't 100% correct: if (for some reason) 2 different resolve_reference
              # calls return the same object, it might not have the right type
              # Right now, apollo-federation just adds a __typename property to the result,
              # but I don't really like the idea of modifying the resolved object
              context[resolved_value] = type
              resolved_value
            end
          end
        end
      end

      # Make sure we've resolved the outer level of lazies so we can return an array with a possibly lazy
      # entry for each requested entity
      GraphQL::Execution::Lazy.all(maybe_lazies).then do
        final_result
      end
    end

    private

    def valid_entity_type?(type)
      return false if type.nil?

      type.kind == GraphQL::TypeKinds::OBJECT || type.kind == GraphQL::TypeKinds::INTERFACE
    end

    def class_of_type(type)
      if (defined?(GraphQL::ObjectType) && type.is_a?(GraphQL::ObjectType)) ||
         (defined?(GraphQL::InterfaceType) && type.is_a?(GraphQL::InterfaceType))
        type.metadata[:type_class]
      else
        type
      end
    end
  end
end

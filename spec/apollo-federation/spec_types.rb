# frozen_string_literal: true

module SpecTypes

  class User
    attr_reader :id, :name

    def initialize(id, name)
      @id = id
      @name = name
    end
  end

  class BaseField < GraphQL::Schema::Field
    include ApolloFederation::Field
  end

  class BaseObject < GraphQL::Schema::Object
    include ApolloFederation::Object
    field_class BaseField
  end

  module BaseInterface
    include GraphQL::Schema::Interface
    include ApolloFederation::Interface

    field_class BaseField
  end

  module InvalidInterface
    include BaseInterface
    key fields: :id

    field :id, ID, null: false
  end

  class InvalidImplementation < BaseObject
    implements InvalidInterface
  end

  module UserType
    include BaseInterface
    key fields: :id

    field :id, ID, null: false
    field :name, String, null: false

    definition_methods do
      def resolve_references(*_args)
        raise 'must be implemented or mocked in test'
      end

      def resolve_type(*_args)
        raise 'must be implemented or mocked in test'
      end
    end
  end

  class AdminType < BaseObject
    implements UserType
    key fields: :id
  end

  class CustomerType < BaseObject
    implements UserType
    key fields: :id
  end
end

# A collection of types which implement the same fields
#
# @example An interface with three required fields
#   DeviceInterface = GraphQL::InterfaceType.define do
#     name("Device")
#     description("Hardware devices for computing")
#
#     field :ram, types.String
#     field :processor, ProcessorType
#     field :release_year, types.Int
#   end
#
class GraphQL::InterfaceType < GraphQL::BaseType
  include GraphQL::BaseType::HasPossibleTypes
  defined_by_config :name, :description, :fields, :resolve_type
  attr_accessor :name, :description, :fields

  def kind
    GraphQL::TypeKinds::INTERFACE
  end

  # @return [Array<GraphQL::ObjectType>] Types which declare that they implement this interface
  def possible_types
    @possible_types ||= []
  end
end

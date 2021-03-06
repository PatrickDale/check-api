PublicTeamType = GraphqlCrudOperations.define_default_type do
  name 'PublicTeam'
  description 'Public team type'

  interfaces [NodeIdentification.interface]

  field :id, field: GraphQL::Relay::GlobalIdField.new('PublicTeam')
  field :name, !types.String
  field :slug, !types.String
  field :description, types.String
  field :dbid, types.Int
  field :avatar, types.String
  field :private, types.Boolean
end

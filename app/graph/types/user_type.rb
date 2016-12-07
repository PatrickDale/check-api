UserType = GraphqlCrudOperations.define_default_type do
  name 'User'
  description 'User type'

  interfaces [NodeIdentification.interface]

  field :id, field: GraphQL::Relay::GlobalIdField.new('User')
  field :email, types.String
  field :provider, types.String
  field :uuid, types.String
  field :profile_image, types.String
  field :login, types.String
  field :name, types.String
  field :current_team_id, types.Int
  field :permissions, types.String

  field :source do
    type SourceType
    resolve -> (user, _args, _ctx) do
      user.source
    end
  end

  field :current_team do
    type TeamType
    resolve -> (user, _args, _ctx) do
      user.current_team
    end
  end

  connection :teams, -> { TeamType.connection_type } do
    resolve ->(user, _args, _ctx) {
      user.teams
    }
  end

  connection :team_users, -> { TeamUserType.connection_type } do
    resolve ->(user, _args, _ctx) {
      user.team_users
    }
  end

  connection :annotations, -> { AnnotationType.connection_type } do
    argument :type, types.String

    resolve ->(user, args, _ctx) {
      type = args['type']
      matches = [{ match: { annotator_type: 'User' } }, { match: { annotator_id: user.id.to_s } }]
      matches << { terms: { annotation_type: [*type] } } unless type.nil?
      query = { bool: { must: matches } }
      params = { query: query, sort: [{ created_at: { order: 'desc' }}, '_score'] }
      ElasticsearchRelation.new(params).all
    }
  end
end

QueryType = GraphQL::ObjectType.define do
  name "Query"
  description "The query root of this schema"

  field :node, field: NodeIdentification.field

  field :root, RootLevelType do
    resolve -> (_obj, _args, _ctx) { RootLevel::STATIC }
  end

  field :about do
    type AboutType
    description 'Information about the application'
    resolve -> (_obj, _args, _ctx) do
      OpenStruct.new({ name: Rails.application.class.parent_name, version: VERSION, id: 1, type: 'About', tos: CONFIG['terms_of_service'], privacy_policy: CONFIG['privacy_policy'], max_upload_size: UploadedFile.max_size_readable })
    end
  end

  field :me do
    type UserType
    description 'Information about the current user'
    resolve -> (_obj, _args, _ctx) do
      User.current
    end
  end

  # Get team by id or slug

  field :team do
    type TeamType
    description 'Information about the context team or the team from given id'
    argument :id, types.ID
    argument :slug, types.String
    resolve -> (_obj, args, ctx) do
      tid = args['id'].to_i
      if !args['slug'].blank?
        team = Team.where(slug: args['slug']).first
        tid = team.id unless team.nil?
      end  
      if tid === 0 && !Team.current.blank?
        tid = Team.current.id
      end
      GraphqlCrudOperations.load_if_can(Team, tid, ctx)
    end
  end

  # Get public team

  field :public_team do
    type PublicTeamType
    description 'Public information about a team'
    argument :slug, types.String

    resolve -> (_obj, args, _ctx) do
      team = args['slug'].blank? ? Team.current : Team.where(slug: args['slug']).last
      id = team.blank? ? 0 : team.id
      Team.find(id)
    end
  end

  field :project_media do
    type ProjectMediaType
    description 'Information about a project media, The argument should be given like this: "project_media_id,project_id"'
    argument :ids, !types.String
    resolve -> (_obj, args, ctx) do
      pmid, pid = args['ids'].split(',').map(&:to_i)
      tid = Team.current.blank? ? 0 : Team.current.id
      project = Project.where(id: pid, team_id: tid).last
      pid = project.nil? ? 0 : project.id
      project_media = ProjectMedia.where(project_id: pid, id: pmid).last
      project_media = ProjectMedia.where(project_id: pid, media_id: pmid).last if project_media.nil?
      pmid = project_media.nil? ? 0 : project_media.id
      GraphqlCrudOperations.load_if_can(ProjectMedia, pmid, ctx)
    end
  end

  field :project do
    type ProjectType
    description 'Information about a project, given its id and its team id'

    argument :id, !types.ID

    resolve -> (_obj, args, ctx) do
      tid = Team.current.blank? ? 0 : Team.current.id
      project = Project.where(id: args['id'], team_id: tid).last
      id = project.nil? ? 0 : project.id
      GraphqlCrudOperations.load_if_can(Project, id, ctx)
    end
  end

  field :search do
    type CheckSearchType
    description 'Search medias, The argument should be given like this: "{\"keyword\":\"search keyword\"}"'

    argument :query, !types.String

    resolve -> (_obj, args, _ctx) do
      CheckSearch.new(args['query'])
    end
  end

  # Getters by ID

  [:source, :user].each do |type|
    field type do
      type "#{type.to_s.camelize}Type".constantize
      description "Information about the #{type} with given id"
      argument :id, !types.ID
      resolve -> (_obj, args, ctx) do
        GraphqlCrudOperations.load_if_can(type.to_s.camelize.constantize, args['id'], ctx)
      end
    end
  end
end

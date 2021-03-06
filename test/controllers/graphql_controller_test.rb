require File.join(File.expand_path(File.dirname(__FILE__)), '..', 'test_helper')

class GraphqlControllerTest < ActionController::TestCase
  def setup
    super
    @controller = Api::V1::GraphqlController.new
    @url = 'https://www.youtube.com/user/MeedanTube'
    require 'sidekiq/testing'
    Sidekiq::Testing.inline!
    User.unstub(:current)
    Team.unstub(:current)
    User.current = nil
  end

  test "should not access GraphQL if not authenticated" do
    post :create, query: 'query Query { about { name, version } }'
    assert_response 401
  end

  test "should access GraphQL if authenticated" do
    authenticate_with_user
    post :create, query: 'query Query { about { name, version, max_upload_size } }', variables: '{"foo":"bar"}'
    assert_response :success
    data = JSON.parse(@response.body)['data']['about']
    assert_kind_of String, data['name']
    assert_kind_of String, data['version']
  end

  test "should get node from global id" do
    authenticate_with_user
    id = Base64.encode64('About/1')
    post :create, query: "query Query { node(id: \"#{id}\") { id } }"
    assert_equal id, JSON.parse(@response.body)['data']['node']['id']
  end

  test "should get current user" do
    u = create_user name: 'Test User'
    authenticate_with_user(u)
    post :create, query: 'query Query { me { name } }'
    assert_response :success
    data = JSON.parse(@response.body)['data']['me']
    assert_equal 'Test User', data['name']
  end

  test "should get current user if logged in with token" do
    u = create_user name: 'Test User'
    authenticate_with_user_token(u.token)
    post :create, query: 'query Query { me { name } }'
    assert_response :success
    data = JSON.parse(@response.body)['data']['me']
    assert_equal 'Test User', data['name']
  end

  test "should return 404 if object does not exist" do
    authenticate_with_user
    post :create, query: 'query GetById { project_media(ids: "99999,99999") { id } }'
    assert_response 404
  end

  test "should set context team" do
    authenticate_with_user
    t = create_team slug: 'context'
    post :create, query: 'query Query { about { name, version } }', team: 'context'
    assert_equal t, assigns(:context_team)
  end

  # Test CRUD operations for each model

  test "should create account" do
    PenderClient::Mock.mock_medias_returns_parsed_data(CONFIG['pender_host']) do
      WebMock.disable_net_connect! allow: [CONFIG['elasticsearch_host'].to_s + ':' + CONFIG['elasticsearch_port'].to_s]
      assert_graphql_create('account', { url: @url })
    end
  end

  test "should read accounts" do
    assert_graphql_read('account', 'url')
  end

  test "should update account" do
    u1 = create_user
    u2 = create_user
    assert_graphql_update('account', :user_id, u1.id, u2.id)
  end

  test "should create comment" do
    p = create_project team: @team
    pm = create_project_media project: p
    assert_graphql_create('comment', { text: 'test', annotated_type: 'ProjectMedia', annotated_id: pm.id.to_s })
  end

  test "should read comments" do
    assert_graphql_read('comment', 'text')
  end

  test "should update comment" do
    assert_graphql_update('comment', 'text', 'foo', 'bar')
  end

  test "should destroy comment" do
    assert_graphql_destroy('comment')
  end

  test "should create media" do
    p = create_project team: @team
    url = random_url
    pender_url = CONFIG['pender_host'] + '/api/medias'
    response = '{"type":"media","data":{"url":"' + url + '","type":"item"}}'
    WebMock.stub_request(:get, pender_url).with({ query: { url: url } }).to_return(body: response)
    assert_graphql_create('project_media', { project_id: p.id, url: url })
    # create claim report
    assert_graphql_create('project_media', { project_id: p.id, quote: 'media quote' })
  end

  test "should create project media" do
    p = create_project team: @team
    m = create_valid_media
    assert_graphql_create('project_media', { media_id: m.id, project_id: p.id })
  end

  test "should read project medias" do
    Media.any_instance.stubs(:published).returns(Time.now.to_i.to_s)
    assert_graphql_read('project_media', 'published')
    #assert_graphql_read('project_media', 'last_status')
  end

  test "should read project media and fallback to media" do
    authenticate_with_user
    p = create_project team: @team
    p2 = create_project team: @team
    m = create_valid_media
    pm = create_project_media project: p, media: m
    pm2 = create_project_media project: p2, media: m
    m2 = create_valid_media
    pm3 = create_project_media project: p, media: m2
    query = "query GetById { project_media(ids: \"#{pm3.id},#{p.id}\") { dbid } }"
    post :create, query: query, team: @team.slug
    assert_response :success
    assert_equal pm3.id, JSON.parse(@response.body)['data']['project_media']['dbid']
    query = "query GetById { project_media(ids: \"#{m2.id},#{p.id}\") { dbid } }"
    post :create, query: query, team: @team.slug
    assert_response :success
    assert_equal pm3.id, JSON.parse(@response.body)['data']['project_media']['dbid']
  end

  test "should read project media embed" do
    authenticate_with_user
    p = create_project team: @team
    p2 = create_project team: @team
    pender_url = CONFIG['pender_host'] + '/api/medias'
    url = 'http://test.com'
    response = '{"type":"media","data":{"url":"' + url + '/normalized","type":"item", "title": "test media", "description":"add desc"}}'
    WebMock.stub_request(:get, pender_url).with({ query: { url: url } }).to_return(body: response)
    m = create_media(account: create_valid_account, url: url)
    pm1 = create_project_media project: p, media: m
    pm2 = create_project_media project: p2, media: m
    # Update media title and description with context p
    info = {title: 'Title A', description: 'Desc A'}.to_json
    pm1.embed = info
    # Update media title and description with context p2
    info = {title: 'Title B', description: 'Desc B'}.to_json
    pm2.embed= info
    query = "query GetById { project_media(ids: \"#{pm1.id},#{p.id}\") { embed } }"
    post :create, query: query, team: @team.slug
    assert_response :success
    embed = JSON.parse(@response.body)['data']['project_media']['embed']
    assert_equal 'Title A', JSON.parse(embed)['title']
    query = "query GetById { project_media(ids: \"#{pm2.id},#{p2.id}\") { embed } }"
    post :create, query: query, team: @team.slug
    assert_response :success
    embed = JSON.parse(@response.body)['data']['project_media']['embed']
    assert_equal 'Title B', JSON.parse(embed)['title']
  end

  test "should read annotations version" do
    authenticate_with_user
    p = create_project team: @team
    pm = create_project_media project: p
    s = pm.get_annotations('status').last
    s = s.nil? ? create_status(annotated: pm, status: false) : s.load
    s.status = 'verified'; s.save!; s.reload
    s.status = 'false'; s.save!
    query = "query GetById { project_media(ids: \"#{pm.id},#{p.id}\") { annotations { edges { node { version { dbid } } } } } }"
    post :create, query: query, team: @team.slug
    assert_response :success
    versions = JSON.parse(@response.body)['data']['project_media']['annotations']['edges']
    assert_equal s.versions.last.id, versions.last["node"]["version"]["dbid"]
  end

  test "should create project source" do
    s = create_source
    p = create_project team: @team
    assert_graphql_create('project_source', { source_id: s.id, project_id: p.id })
  end

  test "should read project sources" do
    assert_graphql_read('project_source', 'source_id')
  end

  test "should update project source" do
    p1 = create_project team: @team
    p2 = create_project team: @team
    assert_graphql_update('project_source', :project_id, p1.id, p2.id)
  end

  test "should destroy project source" do
    assert_graphql_destroy('project_source')
  end

  test "should create project" do
    assert_graphql_create('project', { title: 'test', description: 'test' })
  end

  test "should read project" do
    assert_graphql_read('project', 'title')
  end

  test "should update project" do
    assert_graphql_update('project', :title, 'foo', 'bar')
  end

  test "should destroy project" do
    assert_graphql_destroy('project')
  end

  test "should create source" do
    assert_graphql_create('source', { name: 'test', slogan: 'test' })
  end

  test "should read source" do
    Source.delete_all
    assert_graphql_read('source', 'image')
  end

  test "should update source" do
    assert_graphql_update('source', :name, 'foo', 'bar')
  end

  test "should create team" do
    assert_graphql_create('team', { name: 'test', description: 'test', slug: 'test' })
  end

  test "should read team" do
    assert_graphql_read('team', 'name')
  end

  test "should update team" do
    assert_graphql_update('team', :name, 'foo', 'bar')
  end

  test "should destroy team" do
    assert_graphql_destroy('team')
  end

  test "should create team user" do
    u = create_user
    assert_graphql_create('team_user', { team_id: @team.id, user_id: u.id, status: 'member' })
  end

  test "should read team user" do
    assert_graphql_read('team_user', 'user_id')
  end

  test "should update team user" do
    t = create_team
    assert_graphql_update('team_user', :team_id, t.id, @team.id)
  end

  test "should read user" do
    assert_graphql_read('user', 'email')
  end

  test "should update user" do
    assert_graphql_update('user', :name, 'Foo', 'Bar')
  end

  test "should destroy user" do
    assert_graphql_destroy('user')
  end

  test "should read object from project" do
    assert_graphql_read_object('project', { 'team' => 'name' })
  end

  test "should read object from account" do
    assert_graphql_read_object('account', { 'user' => 'name', 'source' => 'name' })
  end

  test "should read object from project media" do
    assert_graphql_read_object('project_media', { 'project' => 'title', 'media' => 'url', 'last_status_obj' => 'status'})
  end

  test "should read object from project source" do
    assert_graphql_read_object('project_source', { 'project' => 'title', 'source' => 'name' })
  end

  test "should read object from team user" do
    assert_graphql_read_object('team_user', { 'team' => 'name', 'user' => 'name' })
  end

  test "should read collection from source" do
    assert_graphql_read_collection('source', { 'projects' => 'title', 'accounts' => 'url', 'project_sources' => 'project_id',
                                               'annotations' => 'content','medias' => 'media_id', 'collaborators' => 'name',
                                               'tags'=> 'tag', 'comments' => 'text' }, 'DESC')
  end

  test "should read collection from project media" do
    assert_graphql_read_collection('project_media', { 'tags'=> 'tag' })
  end

  test "should read collection from project" do
    assert_graphql_read_collection('project', { 'sources' => 'name', 'project_medias' => 'media_id' })
  end

  test "should read object from media" do
    assert_graphql_read_object('media', { 'account' => 'url' })
  end

  test "should read collection from team" do
    assert_graphql_read_collection('team', { 'team_users' => 'user_id', 'users' => 'name', 'contacts' =>  'location', 'projects' => 'title' })
  end

  test "should read collection from account" do
    assert_graphql_read_collection('account', { 'medias' => 'url' })
  end

  test "should read object from annotation" do
    assert_graphql_read_object('annotation', { 'annotator' => 'name' })
  end

  test "should read object from user" do
    User.any_instance.stubs(:current_team).returns(create_team)
    assert_graphql_read_object('user', { 'source' => 'name', 'current_team' => 'name' })
    User.any_instance.unstub(:current_team)
  end

  test "should read collection from user" do
    assert_graphql_read_collection('user', { 'teams' => 'name', 'team_users' => 'role' })
  end

  test "should create status" do
    s = create_source
    p = create_project team: @team
    ps = create_project_source project: p, source: s
    assert_graphql_create('status', { status: 'credible', annotated_type: 'ProjectSource', annotated_id: ps.id.to_s })
  end

  test "should read statuses" do
    assert_graphql_read('status', 'status')
  end

  test "should destroy status" do
    assert_graphql_destroy('status')
  end

  test "should create tag" do
    p = create_project team: @team
    pm = create_project_media project: p
    assert_graphql_create('tag', { tag: 'egypt', annotated_type: 'ProjectMedia', annotated_id: pm.id.to_s })
  end

  test "should read tags" do
    assert_graphql_read('tag', 'tag')
  end

  test "should destroy tag" do
    assert_graphql_destroy('tag')
  end

  test "should read annotations" do
    assert_graphql_read('annotation', 'annotated_id')
  end

  test "should destroy annotation" do
    assert_graphql_destroy('annotation')
  end

  test "should read versions" do
    assert_graphql_read('version', 'dbid')
  end

  test "should get source by id" do
    assert_graphql_get_by_id('source', 'name', 'Test')
  end

  test "should get user by id" do
    assert_graphql_get_by_id('user', 'name', 'Test')
  end

  test "should get team by id" do
    assert_graphql_get_by_id('team', 'name', 'Test')
  end

  test "should return validation error" do
    authenticate_with_user
    url = 'https://www.youtube.com/user/MeedanTube'

    PenderClient::Mock.mock_medias_returns_parsed_data(CONFIG['pender_host']) do
      WebMock.disable_net_connect! allow: [CONFIG['elasticsearch_host'].to_s + ':' + CONFIG['elasticsearch_port'].to_s]
      query = 'mutation create { createAccount(input: { clientMutationId: "1", url: "' + url + '" }) { account { id } } }'

      assert_difference 'Account.count' do
        post :create, query: query
      end
      assert_response :success

      assert_no_difference 'Account.count' do
        post :create, query: query
      end
      assert_response 400
    end
  end

  test "should create contact" do
    assert_graphql_create('contact', { location: 'my location', phone: '00201099998888', team_id: @team.id })
  end

  test "should read contact" do
    assert_graphql_read('contact', 'location')
  end

  test "should update contact" do
    assert_graphql_update('contact', :location, 'foo', 'bar')
  end

  test "should destroy contact" do
    assert_graphql_destroy('contact')
  end

  test "should read object from contact" do
    assert_graphql_read_object('contact', { 'team' => 'name' })
  end

  test "should get access denied on source by id" do
    authenticate_with_user
    s = create_source user: create_user
    query = "query GetById { source(id: \"#{s.id}\") { name } }"
    post :create, query: query
    assert_response 403
  end

  test "should get team by context" do
    authenticate_with_user
    t = create_team slug: 'context', name: 'Context Team'
    post :create, query: 'query Team { team { name } }', team: 'context'
    assert_response :success
    assert_equal 'Context Team', JSON.parse(@response.body)['data']['team']['name']
  end

  test "should get public team by context" do
    authenticate_with_user
    t1 = create_team slug: 'team1', name: 'Team 1'
    t2 = create_team slug: 'team2', name: 'Team 2'
    post :create, query: 'query PublicTeam { public_team { name } }', team: 'team1'
    assert_response :success
    assert_equal 'Team 1', JSON.parse(@response.body)['data']['public_team']['name']
  end

  test "should get public team by slug" do
    authenticate_with_user
    t1 = create_team slug: 'team1', name: 'Team 1'
    t2 = create_team slug: 'team2', name: 'Team 2'
    post :create, query: 'query PublicTeam { public_team(slug: "team2") { name } }', team: 'team1'
    assert_response :success
    assert_equal 'Team 2', JSON.parse(@response.body)['data']['public_team']['name']
  end

  test "should not get team by context" do
    authenticate_with_user
    t = create_team slug: 'context', name: 'Context Team'
    post :create, query: 'query Team { team { name } }', team: 'test'
    assert_response 404
  end

  test "should update current team based on context team" do
    u = create_user

    t1 = create_team slug: 'team1'
    create_team_user user: u, team: t1
    t2 = create_team slug: 'team2'
    t3 = create_team slug: 'team3'
    create_team_user user: u, team: t3

    u.current_team_id = t1.id
    u.save!

    assert_equal t1, u.reload.current_team

    authenticate_with_user(u)

    post :create, query: 'query Query { me { name } }', team: 'team1'
    assert_response :success
    assert_equal t1, u.reload.current_team

    post :create, query: 'query Query { me { name } }', team: 'team2'
    assert_response :success
    assert_equal t1, u.reload.current_team

    post :create, query: 'query Query { me { name } }', team: 'team3'
    assert_response :success
    assert_equal t3, u.reload.current_team
  end

  test "should get project media annotations" do
    u = create_user
    authenticate_with_user(u)
    t = create_team slug: 'team'
    create_team_user user: u, team: t
    p = create_project team: t
    m = create_media
    pm = create_project_media project: p, media: m
    create_comment annotated: pm, annotator: u
    query = "query GetById { project_media(ids: \"#{pm.id},#{p.id}\") { last_status, domain, pusher_channel, account { url }, dbid, annotations_count, user { name }, tags(first: 1) { edges { node { tag } } }, annotations(first: 1) { edges { node { permissions, medias(first: 5) { edges { node { url } } } } } }, projects { edges { node { title } } } } }"
    post :create, query: query, team: 'team'
    assert_response :success
  end

  test "should get permissions for child objects" do
    u = create_user
    authenticate_with_user(u)
    t = create_team slug: 'team'
    create_team_user user: u, team: t
    p = create_project team: t
    pm = create_project_media project: p
    create_comment annotated: pm, annotator: u
    query = "query GetById { project(id: \"#{p.id}\") { medias_count, project_medias(first: 1) { edges { node { permissions } } } } }"
    post :create, query: query, team: 'team'
    assert_response :success
    assert_not_equal '{}', JSON.parse(@response.body)['data']['project']['project_medias']['edges'][0]['node']['permissions']
  end

  test "should get team with statuses" do
    u = create_user
    authenticate_with_user(u)
    t = create_team slug: 'team'
    create_team_user user: u, team: t, role: 'owner'
    query = "query GetById { team(id: \"#{t.id}\") { media_verification_statuses, source_verification_statuses } }"
    post :create, query: query, team: 'team'
    assert_response :success
  end

  test "should get media statuses" do
    u = create_user
    authenticate_with_user(u)
    t = create_team slug: 'team'
    create_team_user user: u, team: t
    p = create_project team: t
    m = create_media project_id: p.id
    query = "query GetById { media(ids: \"#{m.id},#{p.id}\") { verification_statuses } }"
    post :create, query: query, team: 'team'
    assert_response :success
  end

  test "should get project media team" do
    u = create_user
    authenticate_with_user(u)
    t = create_team slug: 'team'
    create_team_user user: u, team: t
    p = create_project team: t
    pm = create_project_media project: p
    query = "query GetById { project_media(ids: \"#{pm.id},#{p.id}\") { team { name } } }"
    post :create, query: query, team: 'team'
    assert_response :success
    assert_equal t.name, JSON.parse(@response.body)['data']['project_media']['team']['name']
  end

  test "should get source statuses" do
    u = create_user
    authenticate_with_user(u)
    t = create_team slug: 'team'
    create_team_user user: u, team: t
    s = create_source team: t
    query = "query GetById { source(id: \"#{s.id}\") { verification_statuses } }"
    post :create, query: query, team: 'team'
    assert_response :success
  end

  test "should search media" do
    u = create_user
    p = create_project team: @team
    m1 = create_valid_media
    pm1 = create_project_media project: p, media: m1, disable_es_callbacks: false
    authenticate_with_user(u)
    pender_url = CONFIG['pender_host'] + '/api/medias'
    url = 'http://test.com'
    response = '{"type":"media","data":{"url":"' + url + '/normalized","type":"item", "title": "title_a", "description":"search_desc"}}'
    WebMock.stub_request(:get, pender_url).with({ query: { url: url } }).to_return(body: response)
    m2 = create_media(account: create_valid_account, url: url)
    pm2 = create_project_media project: p, media: m2, disable_es_callbacks: false
    sleep 1
    query = 'query Search { search(query: "{\"keyword\":\"title_a\",\"projects\":[' + p.id.to_s + ']}") { number_of_results, medias(first: 10) { edges { node { dbid } } } } }'
    post :create, query: query
    assert_response :success
    ids = []
    JSON.parse(@response.body)['data']['search']['medias']['edges'].each do |id|
      ids << id["node"]["dbid"]
    end
    assert_equal [pm2.id], ids
    create_comment text: 'title_a', annotated: pm1, disable_es_callbacks: false
    sleep 1
    query = 'query Search { search(query: "{\"keyword\":\"title_a\",\"sort\":\"recent_activity\",\"projects\":[' + p.id.to_s + ']}") { medias(first: 10) { edges { node { dbid, project_id } } } } }'
    post :create, query: query
    assert_response :success
    ids = []
    JSON.parse(@response.body)['data']['search']['medias']['edges'].each do |id|
      ids << id["node"]["dbid"]
    end
    assert_equal [pm1.id, pm2.id], ids
  end

  test "should search media with multiple projects" do
    u = create_user
    p = create_project team: @team
    p2 = create_project team: @team
    authenticate_with_user(u)
    pender_url = CONFIG['pender_host'] + '/api/medias'
    url = 'http://test.com'
    response = '{"type":"media","data":{"url":"' + url + '/normalized","type":"item", "title": "title_a", "description":"search_desc"}}'
    WebMock.stub_request(:get, pender_url).with({ query: { url: url } }).to_return(body: response)
    m = create_media(account: create_valid_account, url: url)
    pm = create_project_media project: p, media: m, disable_es_callbacks: false
    pm2 = create_project_media project: p2, media: m,  disable_es_callbacks:  false
    sleep 1
    query = 'query Search { search(query: "{\"keyword\":\"title_a\",\"projects\":[' + p.id.to_s + ',' + p2.id.to_s + ']}") { medias(first: 10) { edges { node { dbid, project_id } } } } }'
    post :create, query: query
    assert_response :success
    p_ids = []
    m_ids = []
    JSON.parse(@response.body)['data']['search']['medias']['edges'].each do |id|
      m_ids << id["node"]["dbid"]
      p_ids << id["node"]["project_id"]
    end
    assert_equal [pm.id, pm2.id], m_ids.sort
    assert_equal [p.id, p2.id], p_ids.sort
    pm2.embed= {description: 'new_description'}.to_json
    sleep 1
    query = 'query Search { search(query: "{\"keyword\":\"title_a\",\"projects\":[' + p.id.to_s + ',' + p2.id.to_s + ']}") { medias(first: 10) { edges { node { dbid, project_id, embed } } } } }'
    post :create, query: query
    assert_response :success
    result = {}
    JSON.parse(@response.body)['data']['search']['medias']['edges'].each do |id|
      result[id["node"]["project_id"]] = JSON.parse(id["node"]["embed"])
    end
    assert_equal 'new_description', result[p2.id]["description"]
    assert_equal 'search_desc', result[p.id]["description"]
  end

  test "should return 404 if public team does not exist" do
    authenticate_with_user
    post :create, query: 'query PublicTeam { public_team { name } }', team: 'foo'
    assert_response 404
  end

  test "should run few queries to get project data" do
    n = 17 # Number of media items to be created
    m = 3 # Number of annotations per media
    u = create_user
    authenticate_with_user(u)
    t = create_team slug: 'team'
    create_team_user user: u, team: t
    p = create_project team: t
    n.times do
      pm = create_project_media project: p
      m.times { create_comment annotated: pm, annotator: u }
    end
    query = "query { project(id: \"#{p.id}\") { project_medias(first: 10000) { edges { node { permissions, annotations(first: 10000) { edges { node { permissions } }  } } } } } }"

    assert_queries (5 * n + 14) do
      post :create, query: query, team: 'team'
    end

    assert_response :success
    assert_equal n, JSON.parse(@response.body)['data']['project']['project_medias']['edges'].size
  end

  test "should get node from global id for search" do
   authenticate_with_user
   options = {"keyword"=>"foo", "sort"=>"recent_added", "sort_type"=>"DESC"}.to_json
   id = Base64.encode64("CheckSearch/#{options}")
   post :create, query: "query Query { node(id: \"#{id}\") { id } }"
   assert_equal id, JSON.parse(@response.body)['data']['node']['id']
  end

  test "should create project media with image" do
    u = create_user
    t = create_team
    create_team_user team: t, user: u
    p = create_project team: t
    authenticate_with_user(u)
    path = File.join(Rails.root, 'test', 'data', 'rails.png')
    file = Rack::Test::UploadedFile.new(path, 'image/png')
    query = 'mutation create { createProjectMedia(input: { url: "", quote: "", clientMutationId: "1", project_id: ' + p.id.to_s + ' }) { project_media { id } } }'
    assert_difference 'UploadedImage.count' do
      post :create, query: query, file: file
    end
    assert_response :success
  end

  test "should get team by slug" do
    authenticate_with_user
    t = create_team slug: 'context', name: 'Context Team'
    post :create, query: 'query Team { team(slug: "context") { name } }'
    assert_response :success
    assert_equal 'Context Team', JSON.parse(@response.body)['data']['team']['name']
  end

  test "should get ordered medias" do
    u = create_user
    authenticate_with_user(u)
    t = create_team slug: 'team'
    create_team_user user: u, team: t
    p = create_project team: t
    pms = []
    5.times do
      pms << create_project_media(project: p)
    end
    query = "query { project(id: \"#{p.id}\") { project_medias(first: 4) { edges { node { dbid } } } } }"

    post :create, query: query, team: 'team'

    assert_response :success
    assert_equal pms.last.dbid, JSON.parse(@response.body)['data']['project']['project_medias']['edges'].first['node']['dbid']
  end

  test "should get language from header" do
    authenticate_with_user
    @request.headers['Accept-Language'] = 'pt-BR'
    post :create, query: 'query Query { me { name } }'
    assert_equal :pt, I18n.locale
  end

  test "should get default if language is not supported" do
    authenticate_with_user
    @request.headers['Accept-Language'] = 'es-LA'
    post :create, query: 'query Query { me { name } }'
    assert_equal :en, I18n.locale
  end

  test "should get closest language" do
    authenticate_with_user
    @request.headers['Accept-Language'] = 'es-LA, fr-FR'
    post :create, query: 'query Query { me { name } }'
    assert_equal :fr, I18n.locale
  end
end

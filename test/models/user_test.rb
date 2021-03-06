require File.join(File.expand_path(File.dirname(__FILE__)), '..', 'test_helper')

class UserTest < ActiveSupport::TestCase

  test "should create user" do
    assert_difference 'User.count' do
      create_user
    end
  end

  test "should update and destroy user" do
    u = create_user
    t = create_team
    create_team_user user: u, team: t, role: 'owner'
    u2 = create_user
    create_team_user team: t, user: u2, role: 'editor'
    u2.save!
    
    with_current_user_and_team(u2, t) do
      assert_raise RuntimeError do
        u.save!
      end
      assert_raise RuntimeError do
        u.save!
      end
    end
    
    with_current_user_and_team(u, t) { u2.destroy }
  end

  test "non members should not read users in private team" do
    u = create_user
    t = create_team
    u1 = create_user
    create_team_user user: u1, team: t
    pu = create_user
    pt = create_team private: true
    ptu = create_team_user user: pu, team: pt
    u2 = create_user
    create_team_user user: u2, team: pt
    with_current_user_and_team(u, t) { User.find_if_can(u1.id) }
    assert_raise CheckdeskPermissions::AccessDenied do
      with_current_user_and_team(u, pt) { User.find_if_can(u2.id) }
    end
    with_current_user_and_team(pu, pt) do
      User.find_if_can(u2.id)
      User.find_if_can(u1.id)
    end
    with_current_user_and_team(u, t) { User.find_if_can(u.id) }
    ptu.status = 'requested'; ptu.save!
    assert_raise CheckdeskPermissions::AccessDenied do
      with_current_user_and_team(pu, pt) { User.find_if_can(u2.id) }
    end
  end

  test "should not require password if there is a provider" do
    assert_nothing_raised do
      create_user password: '', provider: 'twitter'
    end
    assert_raises ActiveRecord::RecordInvalid do
      create_user password: '', provider: ''
    end
  end

  test "should not require email" do
    u = nil
    assert_nothing_raised do
      u = create_user email: ''
    end
    assert_equal '', u.reload.email
  end

  test "should output json" do
    u = create_user
    assert_nothing_raised do
      JSON.parse(u.to_json)
    end
  end

  test "should have token" do
    assert_kind_of String, User.token('foo', '123', 'bar', 'test')
  end

  test "should decript token" do
    token = User.token('foo', '123', 'bar', 'test')
    info = User.from_token(token)
    exp = {
      'provider' => 'foo',
      'id' => '123',
      'token' => 'bar',
      'secret' => 'test'
    }
    assert_equal exp, info
  end

  test "should create source when user is created" do
    u = nil
    assert_difference 'Source.count' do
      u = create_user
    end
    assert_equal u.source, Source.last
  end

  test "should not create account if user has no url" do
    assert_no_difference 'Account.count' do
      create_user url: nil, provider: 'facebook'
    end
  end

  test "should not create account if user has no provider" do
    assert_no_difference 'Account.count' do
      create_user provider: '', url: 'http://meedan.com'
    end
  end

  test "should create account if user has provider and url" do
    assert_difference 'Account.count' do
      PenderClient::Mock.mock_medias_returns_parsed_data(CONFIG['pender_host']) do
        WebMock.disable_net_connect! allow: [CONFIG['elasticsearch_host'].to_s + ':' + CONFIG['elasticsearch_port'].to_s]
        create_user provider: 'youtube', url: 'https://www.youtube.com/user/MeedanTube'
      end
    end
  end

  test "should set token if blank" do
    u = create_user token: ''
    assert_not_equal '', u.reload.token
  end

  test "should not set token if not blank" do
    u = create_user token: 'test'
    assert_equal 'test', u.reload.token
  end

  test "should not set login if not blank" do
    u = create_user login: 'test'
    assert_equal 'test', u.reload.login
  end

  test "should set login from name" do
    u = create_user login: '', name: 'Foo Bar', email: ''
    assert_equal 'foo-bar', u.reload.login
  end

  test "should set login from email" do
    u = create_user login: '', name: 'Foo Bar', email: 'foobar@test.com'
    assert_equal 'foobar', u.reload.login
  end

  test "should set uuid" do
    assert_difference 'User.count', 2 do
      create_user login: '', name: 'Foo Bar', email: 'foobar1@test.com', provider: '', uuid: ''
      create_user login: '', name: 'Foo Bar', email: 'foobar2@test.com', provider: '', uuid: ''
    end
  end

  test "should send welcome email when user is created" do
    stub_config 'send_welcome_email_on_registration', true do
      assert_difference 'ActionMailer::Base.deliveries.size', 1 do
        create_user provider: ''
      end
      assert_no_difference 'ActionMailer::Base.deliveries.size' do
        create_user provider: 'twitter'
        create_user provider: 'facebook'
      end
    end

    stub_config 'send_welcome_email_on_registration', false do
      assert_no_difference 'ActionMailer::Base.deliveries.size' do
        create_user provider: ''
        create_user provider: 'twitter'
        create_user provider: 'facebook'
      end
    end
  end

  test "should have projects" do
    p1 = create_project
    p2 = create_project
    u = create_user
    u.projects << p1
    u.projects << p2
    assert_equal [p1, p2].sort, u.projects.sort
  end

  test "should not upload an image that is not an image" do
    assert_no_difference 'User.count' do
      assert_raises ActiveRecord::RecordInvalid do
        create_user image: 'not-an-image.txt', profile_image: nil
      end
    end
  end

  test "should not upload a big logo" do
    assert_no_difference 'User.count' do
      assert_raises ActiveRecord::RecordInvalid do
        create_user image: 'ruby-big.png', profile_image: nil
      end
    end
  end

  test "should not upload a small logo" do
    assert_no_difference 'Team.count' do
      assert_raises ActiveRecord::RecordInvalid do
        create_user image: 'ruby-small.png', profile_image: nil
      end
    end
  end

  test "should have a default uploaded image" do
    u = create_user image: nil, profile_image: nil
    assert_match /user\.png$/, u.profile_image
  end

  test "should get user role" do
    u = create_user
    t = create_team
    tu = create_team_user user: u, team: t , role: 'owner'
    Team.stubs(:current).returns(t)
    assert_equal u.role, 'owner'
    Team.unstub(:current)
  end

  test "verify user role" do
    u = create_user
    t = create_team
    tu = create_team_user user: u, team: t , role: 'editor'
    Team.stubs(:current).returns(t)
    assert u.role? :editor
    assert u.role? :journalist
    assert_not u.role? :owner
    Team.unstub(:current)
  end

  test "should set current team with one of users team" do
    u = create_user
    t = create_team
    u.teams << t; u.save!
    u.current_team_id = t.id; u.save!
    assert_equal u.current_team_id, t.id
    t2 = create_team
    assert_raises ActiveRecord::RecordInvalid do
      u.current_team_id = t2.id
      u.save!
    end
    t3 = create_team
    create_team_user team: t3, user: u, status: 'requested'
    assert_raises ActiveRecord::RecordInvalid do
      u.current_team_id = t3.id
      u.save!
    end
  end

  test "should set and retrieve current team" do
    u = create_user
    assert_nil u.current_team
    t = create_team
    t2 = create_team
    u.teams << t; u.save!
    u.teams << t2; u.save!
    # test fallback for current team
    assert_equal t2, u.current_team
    u.current_team_id = t.id
    u.save!
    assert_equal t, u.current_team
  end

  test "should get user teams" do
     u = create_user
     t1 = create_team
     create_team_user team: t1, user: u
     t2 = create_team
     create_team_user team: t2, user: u, status: 'requested'
     assert_equal [t1.name, t2.name].sort, JSON.parse(u.user_teams).keys.sort
  end

  test "should not crash if account is not created" do
    assert_nothing_raised do
      assert_difference 'User.count' do
        assert_difference 'Source.count' do
          create_user name: 'Test', url: 'http://test.com'
        end
      end
    end
  end

  test "should return whether a user is member of a team" do
    t1 = create_team
    t2 = create_team
    u = create_user
    create_team_user team: t1, user: u
    assert u.is_member_of?(t1)
    assert !u.is_member_of?(t2)
  end

  test "should have settings" do
    u = create_user
    assert_nil u.settings
    assert_nil u.setting(:foo)
    u.set_foo = 'bar'
    u.save!
    assert_equal 'bar', u.reload.setting(:foo)

    assert_raise NoMethodError do
      u.something
    end
  end

  test "should not crash when creating user account" do
    Account.any_instance.stubs(:save).raises(Errno::ECONNREFUSED)
    assert_nothing_raised do
      create_user url: 'http://twitter.com/meedan', provider: 'twitter'
    end
    Account.any_instance.unstub(:save)
  end

  test "should get permissions" do
    u = create_user
    t = create_team
    create_team_user user: u, team: t, role: 'owner'
    user = create_user
    perm_keys = ["read User", "update User", "destroy User", "create Source", "create TeamUser", "create Team", "create Project"].sort

    # load permissions as owner
    with_current_user_and_team(u, t) { assert_equal perm_keys, JSON.parse(user.permissions).keys.sort }
    
    # load as editor
    tu = u.team_users.last; tu.role = 'editor'; tu.save!
    with_current_user_and_team(u, t) { assert_equal perm_keys, JSON.parse(user.permissions).keys.sort }
    
    # load as editor
    tu = u.team_users.last; tu.role = 'editor'; tu.save!
    with_current_user_and_team(u, t) { assert_equal perm_keys, JSON.parse(user.permissions).keys.sort }
    
    # load as journalist
    tu = u.team_users.last; tu.role = 'journalist'; tu.save!
    with_current_user_and_team(u, t) { assert_equal perm_keys, JSON.parse(user.permissions).keys.sort }
    
    # load as contributor
    tu = u.team_users.last; tu.role = 'contributor'; tu.save!
    with_current_user_and_team(u, t) { assert_equal perm_keys, JSON.parse(user.permissions).keys.sort }
    
    # load as authenticated
    tu = u.team_users.last; tu.role = 'editor'; tu.save!
    tu.delete
    with_current_user_and_team(u, t) { assert_equal perm_keys, JSON.parse(user.permissions).keys.sort }
  end

  test "should get handle" do
    u = create_user provider: '', email: 'user@email.com'
    assert_equal 'user@email.com', u.handle
    u = create_user provider: 'facebook', login: 'user', omniauth_info: { 'url' => 'https://facebook.com/10157109339765023' }
    assert_equal 'https://facebook.com/10157109339765023', u.handle
  end

  test "should get handle for Slack" do
    u = create_user provider: 'slack', omniauth_info: { 'extra' => { 'raw_info' => { 'url' => 'https://meedan.slack.com' } } }, login: 'caiosba'
    assert_equal 'caiosba at https://meedan.slack.com', u.handle
  end

  test "should return whether two users are colleagues in a team" do
    u1 = create_user
    u2 = create_user
    t1 = create_team
    t2 = create_team
    t3 = create_team
    create_team_user team: t1, user: u1
    create_team_user team: t2, user: u2
    create_team_user team: t3, user: u1
    assert !u1.is_a_colleague_of?(u2)
    assert !u2.is_a_colleague_of?(u1)
    create_team_user team: t3, user: u2
    assert u1.is_a_colleague_of?(u2)
    assert u2.is_a_colleague_of?(u1)
  end

  test "should require confirmation for e-mail accounts only" do
    u = create_user provider: 'twitter'
    assert !u.send(:confirmation_required?)
    u = create_user provider: ''
    assert u.send(:confirmation_required?)
  end
end

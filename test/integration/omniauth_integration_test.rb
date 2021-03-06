require File.join(File.expand_path(File.dirname(__FILE__)), '..', 'test_helper')

class OmniauthIntegrationTest < ActionDispatch::IntegrationTest
  test "should close in case of failure" do
    get '/api/users/auth/slack/callback', error: 'access_denied'
    assert_redirected_to '/close.html'
  end
end

module Api
  module V1
    class OmniauthCallbacksController < Devise::OmniauthCallbacksController
      include TwitterAuthentication
      include FacebookAuthentication

      def logout
        sign_out current_api_user
        redirect_to (params[:destination] || '/')
      end

      protected

      def start_session_and_redirect(destination = '/')
        auth = request.env['omniauth.auth']
        user = User.from_omniauth(auth)
        unless user.nil?
          session['checkdesk.user'] = user.id
          sign_in(user)
        end
        destination ||= '/'
        redirect_to destination
      end
    end
  end
end
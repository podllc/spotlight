module Spotlight
  module Analytics
    class Ga
      require 'legato'

      extend Legato::Model

      cattr_accessor :pkcs12_key_path, :email, :web_property_id
      cattr_writer :user, :site

      metrics :sessions, :users, :pageviews

      def self.enabled?
        user && site
      end

      def self.for_exhibit exhibit
        path(Spotlight::Engine.routes.url_helpers.exhibit_path(exhibit))
      end

      filter :path, &lambda { |path| contains(:pagePath, "^#{path}") }
          
      def self.user(scope="https://www.googleapis.com/auth/analytics.readonly")
        @user ||= begin
          require 'oauth2'
          require 'google/api_client'

          client = Google::APIClient.new(
            application_name: "spotlight",
            application_version: Spotlight::VERSION
          )
          key = Google::APIClient::PKCS12.load_key(pkcs12_key_path, "notasecret")
          service_account = Google::APIClient::JWTAsserter.new(email, scope, key)
          client.authorization = service_account.authorize
          oauth_client = OAuth2::Client.new("", "", {
            authorize_url: 'https://accounts.google.com/o/oauth2/auth',
            token_url: 'https://accounts.google.com/o/oauth2/token'
          })
          token = OAuth2::AccessToken.new(oauth_client, client.authorization.access_token, expires_in: 1.hour)
          Legato::User.new(token)
        rescue => e
          Rails.logger.info(e)
          nil
        end
      end

      def self.site
        @site ||= user.accounts.first.profiles.first { |x| x.web_property_id = web_property_id }
      end

      def self.exhibit_data exhibit, options
        self.for_exhibit(exhibit).results(site, options).to_a.first || OpenStruct.new(pageviews: 0, users: 0, sessions: 0)
      end

      def self.page_data exhibit, options
        options[:sort] ||= '-pageviews'
        query = self.for_exhibit(exhibit).results(site, options)
        query.dimensions << :page_path
        query.dimensions << :page_title

        query.to_a
      end
    end
  end
end
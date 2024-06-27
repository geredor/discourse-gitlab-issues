# name: discourse-gitlab-issues
# about: Creates a GitLab issue for each new topic in Discourse
# version: 0.1
# authors: German Ortega
# url: https://github.com/geredor/discourse-gitlab-issues

enabled_site_setting :gitlab_integration_enabled

after_initialize do
  require_dependency 'topic'
  require_dependency 'post'
  require_dependency 'category'
  require 'net/http'
  require 'uri'
  require 'json'
  
  class ::Topic
    after_create_commit :create_gitlab_issue

    def create_gitlab_issue
      return unless SiteSetting.gitlab_integration_enabled

      # Prevent "system" and "discobot" from generating new issues from automatic messages
      return if self.user.username == "system" || self.user.username == "discobot"

      project_id = SiteSetting.gitlab_project_id
      private_token = SiteSetting.gitlab_private_token
      api_url = SiteSetting.gitlab_api_url
      
      title = self.title
      
      # Gets the content of the first post as a description
      description = self.posts.first.raw
      
      # Get category name and parent categories
      category = self.category
      category_labels = []
      while category
        category_labels << category.name
        category = category.parent_category
      end
      labels = category_labels.reverse.join(',')
      
      # Build the topic URL
      topic_url = "#{Discourse.base_url}/t/#{self.slug}/#{self.id}"      

      # Get the information of the user who created the topic
      user = self.user
      user_info = "Created by #{user.username} (#{user.title})"

      # Add the topic URL and user information to the description
      description = <<~DESC
        #{description}

        ---
        #{user_info}
        [View Topic](#{topic_url})
      DESC

      
      uri = URI.parse("#{api_url}/projects/#{project_id}/issues")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      
      # Allow self-signed certificates
      # http.verify_mode = OpenSSL::SSL::VERIFY_NONE

      request = Net::HTTP::Post.new(uri.request_uri)
      request['PRIVATE-TOKEN'] = private_token
      request.body = { 
        title: title, 
        description: description,
        labels: labels
      }.to_json
      request.content_type = 'application/json'

      response = http.request(request)
      unless response.code.to_i == 201
        Rails.logger.error("Failed to create GitLab issue: #{response.body}")
      end
    end
  end
end

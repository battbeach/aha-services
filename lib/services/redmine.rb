class AhaServices::Redmine < AhaService
  title 'Redmine'
  service_name 'redmine_issues'

  string :redmine_url
  string :api_key
  select :project,
    collection: -> (meta_data, data) do
      meta_data.projects.collect { |p| [p.name, p.id] }
    end,
    description: "Redmine project that this Aha! product will integrate with."

  PARAMLISTS = {
    version: [:name, :description, :sharing, :status]
  }

#========
# EVENTS
#======

  def receive_installed
    install_projects
  end

  def receive_create_project
    project_name = payload.project_name
    project_identifier = project_name.downcase.squish.gsub( /\s/, '-' )

    create_project project_name, project_identifier
  end

  def receive_create_release
    project_id = data.project_id
    create_version project_id, payload.release
  end

  def receive_create_feature
    project_id = data.project_id
    response_body = create_issue(project_id, payload.feature)
    payload.feature.requirements.each do |requirement|
      create_issue project_id, requirement, parent_id: response_body[:issue][:id]
    end
  end

  def receive_update_project
    id = payload['id']
    new_name = payload['project_name']

    update_project id, new_name
  end

  def receive_update_release
    project_id = data.project_id
    update_version project_id, payload.release
  end

  def receive_delete_project
    id = payload['id']

    delete_project id
  end

  def receive_delete_version
    project_id = payload['project_id']
    version_id = payload['version_id']

    delete_version project_id, version_id
  end

private

#===============
# EVENT METHODS
#=============

  def install_projects
    @meta_data.projects = []

    prepare_request
    response = http_get("#{data.redmine_url}/projects.json")
    process_response(response, 200) do |body|
      body['projects'].each do |project|
        @meta_data.projects << {
          :id => project['id'],
          :name => project['name']
        }
      end
    end
  end

  def create_project name, identifier
    @meta_data.projects ||= []

    prepare_request
    params = { project:{ name: name, identifier: identifier }}
    response = http_post("#{data.redmine_url}/projects.json", params.to_json)
    process_response(response, 200) do |body|
      @meta_data.projects << {
        :id => body['project']['id'],
        :name => body['project']['name']
      }
    end
  end

  def create_version project_id, resource
    @meta_data.projects ||= []
    install_projects if @meta_data.projects.empty?

    params = Hashie::Mash.new({
      version: {
        name: resource.name}})

    prepare_request
    response = http_post "#{data.redmine_url}/projects/#{project_id}/versions.json", params.to_json
    process_response(response, 201) do |body|
      create_integrations resource.reference_num,
        id: body.version.id,
        name: body.version.name,
        url: "#{data.redmine_url}/versions/#{body.version.id}"
    end
  end

  def create_issue project_id, resource, opts={}
    @meta_data.projects ||= []

    params = Hashie::Mash.new({
      issue: {
        tracker_id: opts[:tracker_id] || 2, # feature tracker
        subject: resource.name
    }})
    params[:issue].merge!({parent_issue_id: opts[:parent_id]}) if opts.has_key?(:parent_id)

    release = resource.release

    prepare_request
    response = http_post "#{data.redmine_url}/projects/#{project_id}/issues.json", params.to_json
    process_response response, 201 do |body|
      create_integrations resource.reference_num,
        id: body.issue.id,
        name: body.issue.subject,
        url: "#{data.redmine_url}/projects/#{project_id}/issues/#{body.issue.id}"
      if release && body.issue.fixed_version
        create_integrations release.reference_num,
          id: body.issue.fixed_version.id,
          name: body.issue.fixed_version.name,
          url: "#{data.redmine_url}/version/#{body.issue.fixed_version.id}"
      end
      return body
    end
  end

  def update_project id, new_name
    @meta_data.projects ||= []
    project = find_project id

    prepare_request
    params = { project:{ name: new_name }}
    response = http_put "#{data.redmine_url}/projects/#{id}.json", params.to_json
    process_response(response, 200) do
      if project
        project[:name] = new_name
      else
        @meta_data.projects << {
          :id => id,
          :name => new_name
        }
      end
    end
  end

  def update_version project_id, resource
    @meta_data.projects ||= []
    install_projects if @meta_data.projects.empty?

    params = Hashie::Mash.new({
      version: {
        name: resource.name}})
    resource_integrations = resource.integration_fields.select {|field| field.service_name == 'redmine_issues'}
    version_id = resource_integrations.find {|field| field.name == 'id'}.value

    prepare_request
    response = http_put "#{data.redmine_url}/projects/#{project_id}/versions/#{version_id}.json", params.to_json
    process_response response, 200 do
      logger.info("Updated version #{version_id}")
    end
  end

  def delete_project id
    @meta_data.projects ||= []
    project = find_project id

    prepare_request
    response = http_delete("#{data.redmine_url}/projects/#{id}.json")
    process_response(response, 200) do
      if project
        @meta_data.projects.delete project
      end
    end
  end

  def delete_version project_id, version_id
    project = find_project project_id
    version = find_version project, version_id

    prepare_request
    response = http_delete("#{data.redmine_url}/projects/#{project_id}/versions/#{version_id}.json")
    process_response response, 200 do
      if project && version
        project[:versions].delete version
      else
        install_projects
      end
    end
  end

#==================
# REQUEST HANDLING
#================

  def prepare_request
    http.headers['Content-Type'] = 'application/json'
    http.headers['X-Redmine-API-Key'] = data.api_key
  end

  def process_response(response, *success_codes, &block)
    if success_codes.include?(response.status)
      yield parse(response.body)
    elsif [404, 403, 401, 400].include?(response.status)
      error = parse(response.body)
      error_string = "#{error['code']} - #{error['error']} #{error['general_problem']} #{error['possible_fix']}"
      raise AhaService::RemoteError, "Error code: #{error_string}"
    else
      raise AhaService::RemoteError, "Unhandled error: STATUS=#{response.status} BODY=#{response.body}"
    end
  end

  def parse(body)
    if body.nil? or body.length < 2
      {}
    else
      Hashie::Mash.new JSON.parse(body)
    end
  end

  def create_integrations reference, **fields
    fields.each do |field, value|
      api.create_integration_field(reference, self.class.service_name, field, value)
    end
  end

#=========
# SUPPORT
#=======

  def find_project project_id
    @meta_data.projects.find {|p| p[:id] == project_id }
  end

  def find_version project_id, version_id
    project = project_id.is_a?(Hash) ? project_id : find_project(project_id)
    project[:versions].find {|v| v[:id] == version_id }
  end

  def sanitize_params params, paramlist_name
    paramlist = PARAMLISTS[paramlist_name]
    params.select {|key, value| paramlist.include? key.to_sym}
  end

  def kind_to_tracker_id kind
    case kind
    when "bug_fix"
      1 # bug tracker
    when "research"
      3 # support tracker
    else
      2 # feature tracker
    end
  end

end
class PivotalTrackerStoryResource < PivotalTrackerProjectDependentResource
  def create_from_feature(feature)
    create_from_resource(feature)
  end

  def create_from_requirement(requirement, feature, feature_mapping_id)
    create_from_resource(requirement, feature, feature_mapping_id)
  end

  def update_from_feature(feature_mapping_id, feature)
    update_from_resource(feature_mapping_id, feature)
  end

  def update_from_requirement(requirement_mapping_id, requirement, feature_mapping_id)
    update_from_resource(requirement_mapping_id, requirement, feature_mapping_id)
  end

protected

  def create(story)
    prepare_request
    response = http_post("#{api_url}/projects/#{project_id}/stories", story.to_json)

    process_response(response, 200) do |created_story|
      logger.info("Created story #{created_story.id}")
      return created_story
    end
  end

  def update(story_id, story)
    prepare_request
    response = http_put("#{api_url}/projects/#{project_id}/stories/#{story_id}", story.to_json)
    process_response(response, 200) do |updated_story|
      logger.info("Updated story #{story_id}")
    end
  end

  def add_attachments(story_id, new_attachments)
    if new_attachments.any?
      response = http_post("#{api_url}/projects/#{project_id}/stories/#{story_id}/comments", {file_attachments: new_attachments}.to_json)
      process_response(response, 200) do |updated_story|
        logger.info("Updated story #{story_id}")
      end
    end
  end

  def attachment_resource
    @attachment_resource ||= PivotalTrackerAttachmentResource.new(@service, project_id)
  end

  def create_from_resource(resource, parent_resource = nil, parent_id = nil)
    story_id = nil

    story = {
      name: resource_name(resource),
      description: append_link(html_to_plain(resource.description.body), parent_id),
      story_type: kind_to_story_type(resource.kind || parent_resource.kind),
      created_at: resource.created_at,
      external_id: parent_resource ? parent_resource.reference_num : resource.reference_num,
      integration_id: @service.data.integration.to_i
    }
    file_attachments = attachment_resource.upload(resource.description.attachments | resource.attachments)
    if file_attachments.any?
      story[:comments] = [{file_attachments: file_attachments}]
    end

    created_story = create(story)
    api.create_integration_fields(reference_num_to_resource_type(resource.reference_num), resource.reference_num, @service.class.service_name, {id: created_story.id, url: created_story.url})
    created_story.id
  end

  def update_from_resource(resource_mapping_id, resource, parent_id = nil)
    story = {
      name: resource_name(resource),
      description: append_link(html_to_plain(resource.description.body), parent_id)
    }

    update(resource_mapping_id, story)

    # Add the new attachments.
    new_attachments = update_attachments(resource_mapping_id, resource)
    add_attachments(resource_mapping_id, new_attachments)
  end

  def update_attachments(story_id, resource)
    aha_attachments = resource.attachments.dup | resource.description.attachments.dup

    # Create any attachments that didn't already exist.
    attachment_resource.upload(new_aha_attachments(story_id, aha_attachments))
  end

  def new_aha_attachments(story_id, aha_attachments)
    attachment_resource.all_for_story(story_id).each do |pivotal_attachment|
      # Remove any attachments that match.
      aha_attachments.reject! do |aha_attachment|
        attachments_match(aha_attachment, pivotal_attachment)
      end
    end

    aha_attachments
  end

  def attachments_match(aha_attachment, pivotal_attachment)
    logger.debug("MATCHING: #{aha_attachment.file_name} #{pivotal_attachment.filename} #{aha_attachment.file_size.to_i} #{pivotal_attachment['size'].to_i}")
    aha_attachment.file_name == pivotal_attachment.filename and
      aha_attachment.file_size.to_i == pivotal_attachment['size'].to_i
  end

  def append_link(body, parent_id)
    if parent_id
      "#{body}\n\nRequirement of ##{parent_id}."
    else
      body
    end
  end

  def kind_to_story_type(kind)
    case kind
    when "new", "improvement"
      "feature"
    when "bug_fix"
      "bug"
    when "research"
      "chore"
    else
      "feature"
    end
  end
end

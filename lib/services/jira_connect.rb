require "#{File.dirname(__FILE__)}/jira"

class AhaServices::JiraConnect < AhaServices::Jira
  title "JIRA via Connect"
  caption "Send features to JIRA (supports cloud only)"
  
  install_button
  select :project, collection: ->(meta_data, data) { meta_data.projects.collect{|p| [p.name, p[:key]] } },
    description: "Choose the JIRA project to integrate with, then click 'Load project data' to fetch the configuration for that project.",
    configure_button: "Load project data",
    configure_button_highlight_if: -> (meta_data, data) { meta_data["configuration"]["attribute_project"]["project"] != data["project"] rescue true }
  boolean :send_initiatives, description: "Check to use feature initiatives to create Epics in JIRA Agile"
  select :feature_issue_type, 
    collection: ->(meta_data, data) { 
      meta_data.issue_type_sets[meta_data.projects.detect {|p| p[:key] == data.project}.issue_types].find_all{|i| !i.subtype}.collect{|p| [p.name, p.id] }
    }, description: "JIRA issue type that will be used when sending features. If you are using JIRA Agile then we recommend 'Story'."
  select :requirement_issue_type, 
    collection: ->(meta_data, data) { 
      meta_data.issue_type_sets[meta_data.projects.detect {|p| p[:key] == data.project}.issue_types].find_all{|i| !i.subtype}.collect{|p| [p.name, p.id] }
    }, description: "JIRA issue type that will be used when sending requirements. If you are using JIRA Agile then we recommend 'Sub-task'."
  internal :feature_status_mapping
  internal :field_mapping
  boolean :dont_send_releases, description: "Check to prevent Aha! from creating versions in JIRA and from populating the fixVersions field for issues. For most users this box should not be checked."
  boolean :dont_auto_import, description: "Check to prevent Aha! from automatically importing issues that are related to an issue that is already linked to Aha!"
  boolean :send_tags, description: "Check to synchronize Aha! tags and JIRA labels. We recommend enabling this for new integrations. Enabling this option once features are synced to JIRA may cause tags in Aha! or labels in JIRA to be removed from a feature if the corresponding label or tag doesn't exist in the other system."
  
  callback_url description: "URL to add to the webhooks section of JIRA if you want to automatically import new JIRA issues to Aha!. See the instructions above for configuring the webhook."
  
end

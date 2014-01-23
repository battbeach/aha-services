require 'spec_helper'

describe AhaServices::Redmine do
  context 'class' do
    let(:title) { 'Redmine' }
    let(:service_name) { 'redmine_issues' }
    let(:schema_fields) {
      [
        [:string, :project_name, {}],
        [:string, :redmine_url, {}],
        [:string, :api_key, {}]
      ]
    }

    it "has required title and name" do
      expect(described_class.title).to eq title
      expect(described_class.service_name).to eq service_name
    end

    it "has required schema fields" do
      expect(described_class.schema).to eq schema_fields
    end
  end

  context "installation" do
    let(:service) { described_class.new redmine_url: 'http://localhost:4000', api_key: '123456' }
    let(:raw_response) { raw_fixture('redmine/projects.json') }
    let(:json_response) { JSON.parse(raw_response) }

    before do
      stub_request(:get, "#{service.data.redmine_url}/projects.json").
        to_return(status: 200, body: raw_response, headers: {})
    end

    it "handles installed event" do
      service.receive(:installed)
      service.meta_data.projects.each_with_index do |proj, index|
        proj["name"].should == json_response['projects'][index]['name']
        proj["id"].should == json_response['projects'][index]['id']
      end
    end
  end
end
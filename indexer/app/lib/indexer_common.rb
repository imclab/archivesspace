require 'net/http'
require 'uri'
require 'json'
require 'fileutils'

require 'asutils'
require 'jsonmodel'
require 'jsonmodel_client'
require 'config/config-distribution'

require_relative 'index_batch'


class CommonIndexer

  include JSONModel

  @@record_types = [:accession, :archival_object, :resource,
                    :digital_object, :digital_object_component,
                    :subject, :location, :classification, :classification_term,
                    :event,
                    :agent_person, :agent_software, :agent_family, :agent_corporate_entity]

  @@records_with_children = []
  @@init_hooks = []

  @@resolved_attributes = ['subjects', 'linked_agents', 'linked_records', 'classification', 'digital_object']


  def self.add_indexer_initialize_hook(&block)
    @@init_hooks << block
  end


  def initialize(backend_url)
    @backend_url = backend_url
    @document_prepare_hooks = []
    @extra_documents_hooks = []
    @delete_hooks = []
    @batch_hooks = []
    @current_session = nil

    while true
      begin
        JSONModel::init(:client_mode => true, :url => @backend_url)
        break
      rescue
        $stderr.puts "Connection to backend failed (#{$!}).  Retrying..."
        sleep(5)
      end
    end

    configure_doc_rules

    @@init_hooks.each do |hook|
      hook.call(self)
    end
  end

  def add_agents(doc, record)
    if record['record']['linked_agents']
      # index all linked agents first
      doc['agents'] = record['record']['linked_agents'].collect{|link| link['_resolved']['names'][0]['sort_name']}

      # index the creators only
      creators = record['record']['linked_agents'].select{|link| link['role'] === 'creator'}
      doc['creators'] = creators.collect{|link| link['_resolved']['names'][0]['sort_name']} if not creators.empty?
    end
  end

  def add_subjects(doc, record)
    if record['record']['subjects']
      doc['subjects'] = record['record']['subjects'].map {|s| s['_resolved']['title']}.compact
    end
  end


  def add_audit_info(doc, record)
    ['created_by', 'last_modified_by', 'user_mtime', 'system_mtime', 'create_time'].each do |f|
      doc[f] = record['record'][f] if record['record'].has_key?(f)
    end
  end


  def add_notes(doc, record)
    if record['record']['notes']
      doc['notes'] = record['record']['notes'].to_json
    end
  end


  def add_level(doc, record)
    if record['record'].has_key? 'level'
      doc['level'] = (record['record']['level'] === 'otherlevel') ? record['record']['other_level'] : record['record']['level']
    end
  end



  def configure_doc_rules
    add_document_prepare_hook {|doc, record|
      if doc['primary_type'] == 'archival_object'
        doc['resource'] = record['record']['resource']['ref'] if record['record']['resource']
        doc['title'] = record['record']['display_string']
      end
    }

    add_document_prepare_hook {|doc, record|
      add_subjects(doc, record)
      add_agents(doc, record)
      add_audit_info(doc, record)
      add_notes(doc, record)
      add_level(doc, record)
    }

    add_document_prepare_hook {|doc, record|
      if doc['primary_type'] == 'accession'
        doc['accession_date_year'] = Date.parse(record['record']['accession_date']).year
        doc['identifier'] = (0...4).map {|i| record['record']["id_#{i}"]}.compact.join("-")
        doc['title'] = record['record']['display_string']
      end
    }

    add_document_prepare_hook {|doc, record|
      if doc['primary_type'] == 'subject'
        doc['source'] = record['record']['source']
        doc['first_term_type'] = record['record']['terms'][0]['term_type']
      end
    }

    add_document_prepare_hook {|doc, record|
      if doc['primary_type'] == 'repository'
        doc['repository'] = doc["id"]
        doc['title'] = record['record']['repo_code']
        doc['publish'] = true
        doc['json'] = record['record'].to_json
      end
    }

    add_document_prepare_hook {|doc, record|
      if doc['primary_type'] == 'location' and record['record'].has_key? 'temporary'
        doc['temporary'] = record['record']['temporary']
      end
    }

    add_document_prepare_hook {|doc, record|
      if doc['primary_type'] == 'digital_object_component'
        doc['digital_object'] = record['record']['digital_object']['ref']
        doc['title'] = record['record']['display_string']
      end
    }

    add_document_prepare_hook {|doc, record|
      if doc['primary_type'] == 'subject'
        doc['publish'] = true
      end
    }

    add_document_prepare_hook {|doc, record|
      if doc['primary_type'] == 'resource'
        doc['finding_aid_title'] = record['record']['finding_aid_title'] if record['record']['finding_aid_status'] === 'completed'
      end

      if doc['primary_type'] == 'digital_object'
        doc['digital_object_type'] = record['record']['digital_object_type']
      end
    }

    add_document_prepare_hook {|doc, record|
      if doc['primary_type'] == 'repository'
        doc['repository'] = doc["id"]
      end
    }

    add_document_prepare_hook {|doc, record|
      if doc['primary_type'] == 'event'
        doc['json'] = record['record'].to_json
        doc['event_type'] = record['record']['event_type']
        doc['outcome'] = record['record']['outcome']
      end
    }

    add_document_prepare_hook {|doc, record|
      if ['agent_person', 'agent_family', 'agent_software', 'agent_corporate_entity'].include?(doc['primary_type'])
        doc['json'] = record['record'].to_json
        doc['title'] = record['record']['names'][0]['sort_name']
        doc['authority_id'] = record['record']['names'][0]['authority_id']
        doc['source'] = record['record']['names'][0]['source']
        doc['rules'] = record['record']['names'][0]['rules']
        doc['publish'] = record['record']['publish']

        # Assign the additional type of 'agent'
        doc['types'] << 'agent'
      end
    }

    add_document_prepare_hook {|doc, record|
      doc['external_id'] = Array(record['record']['external_ids']).map do |eid|
        eid['external_id']
      end
    }


    add_document_prepare_hook {|doc, record|
      if ['classification', 'classification_term'].include?(doc['primary_type'])
        doc['classification_path'] = ASUtils.to_json(record['record']['path_from_root'])
      end
    }

    add_document_prepare_hook {|doc, record|
      if doc['primary_type'] == 'classification_term'
        doc['classification'] = record['record']['classification']['ref']
      end
    }


    add_document_prepare_hook {|doc, record|
      records_with_classifications = ['resource', 'accession']

      if records_with_classifications.include?(doc['primary_type']) && record['record']['classification']
        doc['classification_path'] = ASUtils.to_json(record['record']['classification']['_resolved']['path_from_root'])
        doc['classification_uri'] = record['record']['classification']['ref']
      end
    }

    add_document_prepare_hook {|doc, record|
      if ['resource', 'archival_object'].include?(doc['primary_type']) && record['record']['instances'] && record['record']['instances'].length > 0
        doc['location_uris'] = record['record']['instances'].
                                  collect{|instance| instance["container"]}.compact.
                                  collect{|container| container["container_locations"]}.flatten.
                                  collect{|container_location| container_location["ref"]}.uniq
      end
    }


    record_has_children('collection_management')
    add_extra_documents_hook {|record|
      docs = []

      cm = record['record']['collection_management']
      if cm
        parent_type = JSONModel.parse_reference(record['uri'])[:type]
        docs << {
          'id' => "#{record['uri']}##{parent_type}_collection_management",
          'parent_id' => record['uri'],
          'parent_title' => record['record']['title'],
          'parent_type' => parent_type,
          'title' => record['record']['title'],
          'types' => ['collection_management'],
          'primary_type' => 'collection_management',
          'json' => cm.to_json(:max_nesting => false),
          'processing_priority' => cm['processing_priority'],
          'processing_status' => cm['processing_status'],
          'processing_hours_total' => cm['processing_hours_total'],
          'processing_funding_source' => cm['processing_funding_source'],
          'processors' => cm['processors'],
          'suppressed' => record['record']['suppressed'].to_s,
          'repository' => get_record_scope(record['uri']),
          'created_by' => cm['created_by'],
          'last_modified_by' => cm['last_modified_by'],
          'system_mtime' => cm['system_mtime'],
          'user_mtime' => cm['user_mtime'],
          'create_time' => cm['create_time'],
        }
      end

      docs
    }
  end


  def add_document_prepare_hook(&block)
    @document_prepare_hooks << block
  end


  def record_has_children(record_type)
    @@records_with_children << record_type.to_s
  end


  def add_extra_documents_hook(&block)
    @extra_documents_hooks << block
  end


  def add_batch_hook(&block)
    @batch_hooks << block
  end


  def add_delete_hook(&block)
    @delete_hooks << block
  end


  def solr_url
    URI.parse(AppConfig[:solr_url])
  end


  def do_http_request(url, req)
    req['X-ArchivesSpace-Session'] = @current_session

    Net::HTTP.start(url.host, url.port) do |http|
      http.request(req)
    end
  end


  def reset_session
    @current_session = nil
  end


  def login
    if @current_session
      return @current_session
    end

    username = AppConfig[:search_username]
    password = AppConfig[:search_user_secret]

    url = URI.parse(@backend_url + "/users/#{username}/login")

    request = Net::HTTP::Post.new(url.request_uri)
    request.set_form_data("expiring" => "false",
                          "password" => password)

    response = do_http_request(url, request)

    if response.code == '200'
      auth = ASUtils.json_parse(response.body)

      @current_session = auth['session']
      JSONModel::HTTP.current_backend_session = auth['session']

    else
      raise "Authentication to backend failed: #{response.body}"
    end
  end


  def get_record_scope(uri)
    JSONModel.parse_reference(uri)[:repository] || "global"
  end


  def delete_records(records)
    return if records.empty?

    req = Net::HTTP::Post.new("/update")
    req['Content-Type'] = 'application/json'

    # Delete the ID plus any documents that were the child of that ID
    delete_request = {:delete => records.map {|id|
        [{"id" => id},
         {'query' => "parent_id:\"#{id}\""}]}.flatten(1)
    }

    @delete_hooks.each do |hook|
      hook.call(records, delete_request)
    end

    req.body = delete_request.to_json

    response = do_http_request(solr_url, req)
    $stderr.puts "Deleted #{records.length} documents: #{response}"

    if response.code != '200'
      raise "Error when deleting records: #{response.body}"
    end
  end


  # When applying a batch of updates, keep only the most recent version of each record
  def dedupe_by_uri(records)
    result = []
    seen = {}

    records.reverse.each do |record|
      if !seen[record['uri']]
        result << record
        seen[record['uri']] = true
      end
    end

    result.reverse
  end


  def clean_whitespace(doc)
    if doc.is_a?(String) && !doc.frozen?
      doc.strip!
    elsif doc.is_a?(Hash)
      doc.values.each {|v| clean_whitespace(v)}
    elsif doc.is_a?(Array)
      doc.each {|v| clean_whitespace(v)}
    end

    doc
  end


  def index_records(records)
    batch = IndexBatch.new

    records = dedupe_by_uri(records)

    records.each do |record|
      values = record['record']
      uri = record['uri']
      reference = JSONModel.parse_reference(uri)
      record_type = reference && reference[:type]

      if !record_type || (record_type != 'repository' && !@@record_types.include?(record_type.intern))
        next
      end

      doc = {}

      doc['id'] = uri
      doc['title'] = values['title']
      doc['primary_type'] = record_type
      doc['types'] = [record_type]
      doc['json'] = ASUtils.to_json(values)
      doc['suppressed'] = values['suppressed'].to_s
      doc['publish'] = values.has_key?('publish') ? values['publish'].to_s : 'false'
      doc['system_generated'] = values.has_key?('system_generated') ? values['system_generated'].to_s : 'false'
      doc['repository'] = get_record_scope(uri)

      @document_prepare_hooks.each do |hook|
        hook.call(doc, record)
      end

      batch << clean_whitespace(doc)

      # Allow a single record to spawn multiple Solr documents if desired
      @extra_documents_hooks.each do |hook|
        batch.concat(hook.call(record))
      end
    end


    # Allow hooks to operate on the entire batch if desired
    @batch_hooks.each_with_index do |hook|
      hook.call(batch)
    end


    if !batch.empty?
      # For any record we're updating, delete any child records first (where applicable)
      records_with_children = batch.map {|e|
        if @@records_with_children.include?(e['primary_type'].to_s)
          "\"#{e['id']}\""
        end
      }.compact

      if !records_with_children.empty?
        req = Net::HTTP::Post.new("/update")
        req['Content-Type'] = 'application/json'
        req.body = {:delete => {'query' => "parent_id:(" + records_with_children.join(" OR ") + ")"}}.to_json
        response = do_http_request(solr_url, req)
      end

      # Now apply the updates
      req = Net::HTTP::Post.new("/update")
      req['Content-Type'] = 'application/json'

      stream = batch.to_json_stream
      req['Content-Length'] = batch.byte_count

      req.body_stream = stream

      response = do_http_request(solr_url, req)

      stream.close
      batch.destroy

      if response.code != '200'
        raise "Error when indexing records: #{response.body}"
      end
    end

  end


  def send_commit(type = :hard)
    req = Net::HTTP::Post.new("/update")
    req['Content-Type'] = 'application/json'
    req.body = {:commit => {"softCommit" => (type == :soft) }}.to_json

    response = do_http_request(solr_url, req)

    if response.code != '200'
      if response.body =~ /exceeded limit of maxWarmingSearchers/
        $stderr.puts "INFO: #{response.body}"
      else
        raise "Error when committing: #{response.body}"
      end
    end
  end

end


ASUtils.find_local_directories('indexer').each do |dir|
  Dir.glob(File.join(dir, "*.rb")).sort.each do |file|
    require file
  end
end

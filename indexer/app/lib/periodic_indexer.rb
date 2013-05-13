require_relative 'indexer_common'
require 'time'

class IndexState

  def initialize
    @state_dir = File.join(AppConfig[:data_directory], "indexer_state")

    FileUtils.mkdir_p(@state_dir)
  end


  def path_for(repository_id, record_type)
    File.join(@state_dir, "#{repository_id}_#{record_type}")
  end


  def set_last_mtime(repository_id, record_type, time)
    path = path_for(repository_id, record_type)

    File.open("#{path}.tmp", "w") do |fh|
      fh.puts(time.to_i)
    end

    File.rename("#{path}.tmp", "#{path}.dat")
  end


  def get_last_mtime(repository_id, record_type)
    path = path_for(repository_id, record_type)

    begin
      File.open("#{path}.dat", "r") do |fh|
        fh.readline.to_i
      end
    rescue Errno::ENOENT
      # If we've never run against this repository_id/type before, just index
      # everything.
      0
    end
  end
end


class PeriodicIndexer < CommonIndexer

  # A small window to account for the fact that transactions might be committed
  # after the periodic indexer has checked for updates, but with timestamps from
  # prior to the check.
  WINDOW_SECONDS = 30


  def load_tree_docs(tree, result, root_uri, path_to_root = [])
    this_node = tree.reject {|k, v| k == 'children'}

    result << {
      'id' => "tree_view_#{tree['record_uri']}",
      'primary_type' => 'tree_view',
      'exclude_by_default' => 'true',
      'node_uri' => tree['record_uri'],
      'repository' => JSONModel.repository_for(tree['record_uri']),
      'root_uri' => root_uri,
      'publish' => true,
      'tree_json' => ASUtils.to_json(:self => this_node,
                                     :path_to_root => path_to_root,
                                     :direct_children => tree['children'].map {|child|
                                       child.reject {|k, v| k == 'children'}
                                     })
    }

    tree['children'].each do |child|
      load_tree_docs(child, result, root_uri, path_to_root + [this_node])
    end
  end


  def delete_trees_for(resource_uris)
    return if resource_uris.empty?

    resource_uris.each_slice(512) do |resource_uris|
      req = Net::HTTP::Post.new("/update")
      req['Content-Type'] = 'application/json'

      delete_request = {'delete' => {'query' => "primary_type:tree_view AND root_uri:(#{resource_uris.join(' OR ')})"}}

      req.body = delete_request.to_json

      response = do_http_request(solr_url, req)

      if response.code != '200'
        raise "Error when deleting record trees: #{response.body}"
      end
    end
  end


  @processed_trees = []

  def configure_doc_rules
    super

    add_batch_hook {|batch|
      resources = batch.map {|rec| rec['primary_type'] == 'archival_object' ? rec['resource'] : nil}.compact.uniq

      # Don't reprocess trees we've already covered during previous batches
      resources -= @processed_trees

      ## Each resource needs its tree indexed

      # Delete any existing versions
      delete_trees_for(resources)

      # Add the updated versions
      tree_docs = []

      resources.each do |resource_uri|
        id = JSONModel(:resource).id_for(resource_uri)
        tree = JSONModel(:resource_tree).find(nil, :resource_id => id)

        load_tree_docs(tree.to_hash(:trusted), tree_docs, resource_uri)
        @processed_trees << resource_uri
      end

      #TODO digital objects and components too

      batch.concat(tree_docs)
    }
  end

  def initialize(state = nil)
    super(AppConfig[:backend_url])
    @state = state || IndexState.new
  end


  def handle_deletes
    start = Time.now
    last_mtime = @state.get_last_mtime('_deletes', 'deletes')
    did_something = false

    page = 1
    while true
      deletes = JSONModel::HTTP.get_json("/delete-feed", :modified_since => [last_mtime - WINDOW_SECONDS, 0].max, :page => page)

      if !deletes['results'].empty?
        did_something = true
      end

      delete_records(deletes['results'])

      break if deletes['last_page'] <= page

      page += 1
    end

    send_commit if did_something

    @state.set_last_mtime('_deletes', 'deletes', start)
  end


  def run_index_round
    puts "#{Time.now}: Running index round"

    login

    # Set the list of tree URIs back to empty to start over again
    @processed_trees = []

    JSONModel(:repository).all.each do |repository|
      JSONModel.set_repository(repository.id)

      did_something = false
      checkpoints = []

      @@record_types.each do |type|
        start = Time.now
        page = 1
        while true
          modified_since = [@state.get_last_mtime(repository.id, type) - WINDOW_SECONDS, 0].max
          records = JSONModel(type).all(:page => page,
                                        'resolve[]' => @@resolved_attributes,
                                        :modified_since => modified_since)

          # Unlimited results return an array.  Fake pagination.
          if records.kind_of? Array
            records = {
              'results' => records.reject {|record|
                record['last_modified'] && Time.parse(record['last_modified']).to_i < modified_since
              },
              'last_page' => 1
            }
          end

          if !records['results'].empty?
            did_something = true
          end

          index_records(records['results'].map {|record|
                          {
                            'record' => record.to_hash(:trusted),
                            'uri' => record.uri
                          }
                        })

          break if records['last_page'] <= page
          page += 1
        end

        checkpoints << [repository, type, start]
      end

      send_commit if did_something

      checkpoints.each do |repository, type, start|
        @state.set_last_mtime(repository.id, type, start)
      end
    end

    handle_deletes

  end


  def run
    while true
      begin
        run_index_round
      rescue
        reset_session
        puts "#{$!.inspect}"
      end

      sleep AppConfig[:solr_indexing_frequency_seconds].to_i
    end
  end


  def self.get_indexer(state = nil)
    indexer = self.new(state)
  end

end


require_relative 'indexer_common'
require 'time'
require 'thread'

class IndexState

  def initialize
    @state_dir = File.join(AppConfig[:data_directory], "indexer_state")
  end


  def path_for(repository_id, record_type)
    FileUtils.mkdir_p(@state_dir)

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

  THREAD_COUNT = AppConfig[:indexer_thread_count].to_i
  RECORDS_PER_THREAD = AppConfig[:indexer_records_per_thread].to_i

  def load_tree_docs(tree, result, root_uri, path_to_root = [])
    this_node = tree.reject {|k, v| k == 'children'}

    doc = {
      'id' => "tree_view_#{tree['record_uri']}",
      'primary_type' => 'tree_view',
      'types' => ['tree_view'],
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

    # For the root node, store a copy of the whole tree
    if path_to_root.empty?
      doc['whole_tree_json'] = ASUtils.to_json(tree)
    end

    result << doc
    doc = nil

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


  def configure_doc_rules
    super

    @processed_trees = java.util.concurrent.ConcurrentHashMap.new

    add_batch_hook {|batch|
      records = batch.map {|rec|
        if ['resource', 'digital_object', 'classification'].include?(rec['primary_type'])
          rec['id']
        elsif rec['primary_type'] == 'archival_object'
          rec['resource']
        elsif rec['primary_type'] == 'digital_object_component'
          rec['digital_object']
        elsif rec['primary_type'] == 'classification_term'
          rec['classification']
        else
          nil
        end
      }.compact.uniq

      # Don't reprocess trees we've already covered during previous batches
      records -= @processed_trees.keySet

      ## Each record needs its tree indexed

      # Delete any existing versions
      delete_trees_for(records)

      records.each do |record_uri|
        # To avoid all of the indexing threads hitting the same tree at the same
        # moment, use @processed_trees to ensure that only one of them handles
        # it.
        next if @processed_trees.putIfAbsent(record_uri, true)

        record_data = JSONModel.parse_reference(record_uri)

        tree = JSONModel("#{record_data[:type]}_tree".intern).find(nil, "#{record_data[:type]}_id".intern => record_data[:id])

        load_tree_docs(tree.to_hash(:trusted), batch, record_uri)
        @processed_trees.put(record_uri, true)
      end
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
      deletes = JSONModel::HTTP.get_json("/delete-feed", :modified_since => [last_mtime - WINDOW_SECONDS, 0].max, :page => page, :page_size => RECORDS_PER_THREAD)

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


  def start_worker_thread(queue, record_type)
    repo_id = JSONModel.repository
    session = JSONModel::HTTP.current_backend_session

    Thread.new do
      begin
        # Inherit the repo_id and user session from the parent thread
        JSONModel.set_repository(repo_id)
        JSONModel::HTTP.current_backend_session = session

        did_something = false

        while true
          id_subset = queue.pop
          break if id_subset == :finished

          records = JSONModel(record_type).all(:id_set => id_subset.join(","),
                                               'resolve[]' => @@resolved_attributes)

          if !records.empty?
            did_something = true
            index_records(records.map {|record|
                            {
                              'record' => record.to_hash(:trusted),
                              'uri' => record.uri
                            }
                          })
          end
        end

        did_something
      rescue
        $stderr.puts("Failure in periodic indexer worker thread: #{$!}")
        $stderr.puts($!.backtrace)
        raise $!
      end
    end
  end

  def run_index_round
    $stderr.puts "#{Time.now}: Running index round"

    login

    # Index any repositories that were changed
    start = Time.now
    repositories = JSONModel(:repository).all

    modified_since = [@state.get_last_mtime('repositories', 'repositories') - WINDOW_SECONDS, 0].max
    updated_repositories = repositories.reject {|repository| Time.parse(repository['system_mtime']).to_i < modified_since}.
    map {|repository| {
        'record' => repository.to_hash(:trusted),
        'uri' => repository.uri
      }
    }

    if !updated_repositories.empty?
      index_records(updated_repositories)
      send_commit
    end

    @state.set_last_mtime('repositories', 'repositories', start)

    # Set the list of tree URIs back to empty to start over again
    @processed_trees.clear

    # And any records in any repositories
    repositories.each do |repository|
      JSONModel.set_repository(repository.id)

      checkpoints = []

      did_something = false

      @@record_types.each do |type|
        start = Time.now

        modified_since = [@state.get_last_mtime(repository.id, type) - WINDOW_SECONDS, 0].max

        id_set = JSONModel::HTTP.get_json(JSONModel(type).uri_for, :all_ids => true, :modified_since => modified_since)

        next if id_set.empty?

        indexed_count = 0
        work_queue = SizedQueue.new(THREAD_COUNT)

        workers = (0...THREAD_COUNT).map {|thread_idx|
          start_worker_thread(work_queue, type)
        }

        # Feed our worker threads subsets of IDs to process
        id_set.each_slice(RECORDS_PER_THREAD) do |id_subset|
          # This will block if all threads are currently busy.
          work_queue.push(id_subset)

          indexed_count += id_subset.length
          $stderr.puts("Indexed #{indexed_count} of #{id_set.length} #{type} records in repository #{repository.repo_code}")
        end

        # And once we're done, instruct them to finish up and wait for them.  If
        # any of the threads reported that they indexed some records, we'll send
        # a commit.
        THREAD_COUNT.times { work_queue.push(:finished) }
        results = workers.map {|thread| thread.join; thread.value}
        did_something ||= results.any? {|status| status}

        checkpoints << [repository, type, start]

        $stderr.puts("Indexed #{id_set.length} records in #{Time.now.to_i - start.to_i} seconds")
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

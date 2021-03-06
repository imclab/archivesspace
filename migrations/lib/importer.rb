require_relative '../lib/jsonmodel_wrap'
require_relative '../lib/parse_queue'

module ASpaceImport

  def self.init
    Dir.glob(File.dirname(__FILE__) + '/../importers/*', &method(:load))
  end


  class ResponseReader
    def initialize
      @fragments = ""
    end


    def read_response(response)
      response.read_body do |chunk|
        read(chunk) do |message|
          yield message
        end
      end
    end


    def read(chunk)
      begin 
        if chunk =~ /\A\[\n\Z/
          # do nothing because we're treating the response as a stream
        elsif chunk =~ /\A\n\]\Z/
          # the last message doesn't have a comma, so it's a fragment
          s = @fragments.sub(/\n\Z/, '')
          @fragments = ""
          yield ASUtils.json_parse(s)
        elsif chunk =~ /.*,\n\Z/
          s = @fragments + chunk.sub(/,\n\Z/, '')
          @fragments = ""
          yield ASUtils.json_parse(s)
        else
          @fragments << chunk
        end
      rescue JSON::ParserError => e
        yield({:error => e.to_s})
      end
    end
  end


  class Importer

    @@importers = {}

    def self.list
      list = "\nThe following importers are available\n"
      @@importers.each do |i, klass|
        list += "*#{i}* \n#{klass.profile}\n\n"
      end
      list
    end


    def self.create_importer(opts)
      i = @@importers[opts[:importer].to_sym]
      if !i.nil?
        i.new opts
      else
        raise StandardError.new("Unusable importer or importer not found for: #{name}(#{opts[:importer]})")
      end
    end


    def self.destroy_importers
      @@importers.each do |key, klass|
        Object.send(:remove_const, klass.name)
      end
      @@importers = {}
    end


    def self.importer(name, superclass = ASpaceImport::Importer, &block)
      if @@importers.has_key? name
        raise StandardError.new("Attempted to register #{name} a second time")
      else
        c = Class.new(superclass, &block)
        cname_prefix = name.to_s.split(/[_-]/).map {|i| i.capitalize }.join
        Object.const_set("#{cname_prefix}Importer", c)
        @@importers[name] = c
        true
      end
    end


    def initialize(opts = {})

      raise "Need a repo_id in order to run" unless opts[:repo_id]

      unless opts[:log]
        require 'logger'
        opts[:log] = Logger.new(STDOUT)

        if opts[:debug]
          opts[:log].level = Logger::DEBUG
        elsif opts[:quiet]
          opts[:log].level = Logger::UNKNOWN
        else
          opts[:log].level = Logger::WARN
        end
      end


      JSONModel::set_repository(opts[:repo_id])

      @flags = {}
      if opts[:importer_flags]
        opts[:importer_flags].each do |flag|
          @flags[flag] = true
        end
        opts.delete(:importer_flags)
      end

      opts.each do |k,v|
        instance_variable_set("@#{k}", v)
      end

      @block = nil
    end


    def run_safe(&block)

      @block = block
      return nil unless @block

      begin
        emit_status({'type' => 'started', 'label' => 'Beginning Import', 'id' => 'xml'})
        @batch = ASpaceImport::RecordBatch.new({ 
                                                :log => @log, 
                                                :dry => @dry, 
                                                :batch_path => @batch_path, 
                                                :client_block => @block  })
        # implemented by importers
        # to fill the batch
        self.run

        @batch.save! do |response|
          handle_save_response(response)
        end
      rescue JSONModel::ValidationException => e
        errors = e.errors.map{|attr, err| 
          str = "#{e.invalid_object ? e.invalid_object.class.record_type : ''}/#{attr} #{err.join(', ')}"
          if e.invalid_object.respond_to?(:title) 
            str << "\nRecord title: #{e.invalid_object.title}"
          else
            str << "\nInvalid record: #{e.invalid_object.inspect}"
          end
          str
        }
        @block.call({"errors" => errors})
      end
    end


    private

    def handle_save_response(response)
      if response.code.to_s == '200'
        reader = ResponseReader.new
        reader.read_response(response) do |message|
          send_to_client(message)
        end
      else
        send_to_client({"error" => "Server Error #{response.code}"})
      end
    end


    def send_to_client(message)
      if @block
        @block.call(message)
      end
    end


    def emit_status(hsh)
      @block.call({'status' => [hsh]})
    end

  end
end


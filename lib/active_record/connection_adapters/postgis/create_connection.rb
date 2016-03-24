if RUBY_ENGINE == "jruby"
  require "active_record/connection_adapters/jdbcpostgresql_adapter"
else
  require "pg"
end

module ActiveRecord  # :nodoc:
  module ConnectionHandling  # :nodoc:

    # START OF ActiveRecord/ConnectionHandling

    RAILS_ENV   = -> { (Rails.env if defined?(Rails.env)) || ENV["RAILS_ENV"] || ENV["RACK_ENV"] } unless defined? RAILS_ENV
    DEFAULT_ENV = -> { RAILS_ENV.call || "default_env" } unless defined? DEFAULT_ENV

    # Establishes the connection to the database. Accepts a hash as input where
    # the <tt>:adapter</tt> key must be specified with the name of a database adapter (in lower-case)
    # example for regular databases (MySQL, PostgreSQL, etc):
    #
    #   ActiveRecord::Base.establish_connection(
    #     adapter:  "mysql2",
    #     host:     "localhost",
    #     username: "myuser",
    #     password: "mypass",
    #     database: "somedatabase"
    #   )
    #
    # Example for SQLite database:
    #
    #   ActiveRecord::Base.establish_connection(
    #     adapter:  "sqlite3",
    #     database: "path/to/dbfile"
    #   )
    #
    # Also accepts keys as strings (for parsing from YAML for example):
    #
    #   ActiveRecord::Base.establish_connection(
    #     "adapter"  => "sqlite3",
    #     "database" => "path/to/dbfile"
    #   )
    #
    # Or a URL:
    #
    #   ActiveRecord::Base.establish_connection(
    #     "postgres://myuser:mypass@localhost/somedatabase"
    #   )
    #
    # In case {ActiveRecord::Base.configurations}[rdoc-ref:Core.configurations]
    # is set (Rails automatically loads the contents of config/database.yml into it),
    # a symbol can also be given as argument, representing a key in the
    # configuration hash:
    #
    #   ActiveRecord::Base.establish_connection(:production)
    #
    # The exceptions AdapterNotSpecified, AdapterNotFound and +ArgumentError+
    # may be returned on an error.
    def establish_connection(spec = nil)
      spec     ||= DEFAULT_ENV.call.to_sym
      resolver =   ConnectionAdapters::ConnectionSpecification::Resolver.new configurations
      spec     =   resolver.spec(spec)

      unless respond_to?(spec.adapter_method)
        raise AdapterNotFound, "database configuration specifies nonexistent #{spec.config[:adapter]} adapter"
      end

      remove_connection
      connection_handler.establish_connection self, spec
    end

    class MergeAndResolveDefaultUrlConfig # :nodoc:
      def initialize(raw_configurations)
        @raw_config = raw_configurations.dup
        @env = DEFAULT_ENV.call.to_s
      end

      # Returns fully resolved connection hashes.
      # Merges connection information from `ENV['DATABASE_URL']` if available.
      def resolve
        ConnectionAdapters::ConnectionSpecification::Resolver.new(config).resolve_all
      end

      private
      def config
        @raw_config.dup.tap do |cfg|
          if url = ENV['DATABASE_URL']
            cfg[@env] ||= {}
            cfg[@env]["url"] ||= url
          end
        end
      end
    end

    # Returns the connection currently associated with the class. This can
    # also be used to "borrow" the connection to do database work unrelated
    # to any of the specific Active Records.
    def connection
      retrieve_connection
    end

    def connection_id
      ActiveRecord::RuntimeRegistry.connection_id ||= Thread.current.object_id
    end

    def connection_id=(connection_id)
      ActiveRecord::RuntimeRegistry.connection_id = connection_id
    end

    # Returns the configuration of the associated connection as a hash:
    #
    #  ActiveRecord::Base.connection_config
    #  # => {pool: 5, timeout: 5000, database: "db/development.sqlite3", adapter: "sqlite3"}
    #
    # Please use only for reading.
    def connection_config
      connection_pool.spec.config
    end

    def connection_pool
      connection_handler.retrieve_connection_pool(self) or raise ConnectionNotEstablished
    end

    def retrieve_connection
      connection_handler.retrieve_connection(self)
    end

    # Returns +true+ if Active Record is connected.
    def connected?
      connection_handler.connected?(self)
    end

    def remove_connection(klass = self)
      connection_handler.remove_connection(klass)
    end

    def clear_cache! # :nodoc:
      connection.schema_cache.clear!
    end

    delegate :clear_active_connections!, :clear_reloadable_connections!,
             :clear_all_connections!, :to => :connection_handler

    # END OF ActiveRecord/ConnectionHandling



    if RUBY_ENGINE == "jruby"

      def postgis_connection(config)
        config[:adapter_class] = ConnectionAdapters::PostGISAdapter
        postgresql_connection(config)
      end

      alias_method :jdbcpostgis_connection, :postgis_connection

    else
      # Based on the default <tt>postgresql_connection</tt> definition from ActiveRecord.
      # https://github.com/rails/rails/blob/master/activerecord/lib/active_record/connection_adapters/postgresql_adapter.rb
      def postgis_connection(config)
        # FULL REPLACEMENT because we need to create a different class.
        conn_params = config.symbolize_keys

        conn_params.delete_if { |_, v| v.nil? }

        # Map ActiveRecords param names to PGs.
        conn_params[:user] = conn_params.delete(:username) if conn_params[:username]
        conn_params[:dbname] = conn_params.delete(:database) if conn_params[:database]

        # Forward only valid config params to PGconn.connect.
        conn_params.keep_if { |k, _| VALID_CONN_PARAMS.include?(k) }

        # The postgres drivers don't allow the creation of an unconnected PGconn object,
        # so just pass a nil connection object for the time being.
        ConnectionAdapters::PostGISAdapter.new(nil, logger, conn_params, config)
      end

    end
  end
end

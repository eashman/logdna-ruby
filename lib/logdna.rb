# frozen_string_literal: true

require "logger"
require "socket"
require "uri"
require_relative "logdna/client"
require_relative "logdna/resources"
require_relative "logdna/version"

module Logdna
  class ValidURLRequired < ArgumentError; end

  class MaxLengthExceeded < ArgumentError; end

  class Ruby < ::Logger
    include ActiveSupport::LoggerSilence
    # uncomment line below and line 3 to enforce singleton
    # include Singleton
    Logger::TRACE = 5
    attr_accessor :app, :env, :meta

    def initialize(key, opts = {})
      @app = opts[:app] || "default"
      @env = opts[:env]
      @meta = opts[:meta]
      @internal_logger = Logger.new($stdout)
      @internal_logger.level = Logger::DEBUG
      endpoint = opts[:endpoint] || Resources::ENDPOINT
      hostname = opts[:hostname] || Socket.gethostname

      if hostname.size > Resources::MAX_INPUT_LENGTH || @app.size > Resources::MAX_INPUT_LENGTH
        @internal_logger.debug("Hostname or Appname is over #{Resources::MAX_INPUT_LENGTH} characters")
        return
      end

      ip =  opts.key?(:ip) ? "&ip=#{opts[:ip]}" : ""
      mac = opts.key?(:mac) ? "&mac=#{opts[:mac]}" : ""
      url = "#{endpoint}?hostname=#{hostname}#{mac}#{ip}"
      uri = URI(url)

      request = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
      request.basic_auth("username", key)
      request[:'user-agent'] = opts[:'user-agent'] || "ruby/#{LogDNA::VERSION}"
      @client = Logdna::Client.new(request, uri, opts)

      super(nil, nil, nil, level: opts[:level] || "INFO")
    end

    def default_opts
      {
        app: @app,
        level: level,
        env: @env,
        meta: @meta,
      }
    end

    def level=(value)
      return super(value) if value.is_a?(Integer)
      return super(Resources::TRACE) if value.to_s.downcase == 'trace'

      super
    end

    def log(message = nil, opts = {})
      if message.nil? && block_given?
        message = yield
      end
      if message.nil?
        @internal_logger.debug("provide either a message or block")
        return
      end
      message = message.to_s.encode("UTF-8")
      @client.write_to_buffer(message, default_opts.merge(opts).merge(
        timestamp: (Time.now.to_f * 1000).to_i
      ))
    end

    Resources::LOG_LEVELS.each do |lvl|
      name = lvl.downcase

      define_method name do |msg = nil, opts = {}, &block|
        self.log(msg, opts.merge(
          level: lvl
        ), &block)
      end
    end

    def trace?
      level <= Resources::TRACE
    end

    def clear
      @app = "default"
      level = Resources::LOG_LEVELS[1]
      @env = nil
      @meta = nil
    end

    def <<(msg = nil, opts = {})
      log(msg, opts.merge(
        level: ""
      ))
    end

    def add(*_arg)
      #@internal_logger.debug("add not supported in LogDNA logger")
      false
    end

    def unknown(msg = nil, opts = {})
      log(msg, opts.merge(
        level: "UNKNOWN"
      ))
    end

    def datetime_format(*_arg)
      @internal_logger.debug("datetime_format not supported in LogDNA logger")
      false
    end

    def close
      @client&.exitout
    end
  end
end

require 'optparse'
require 'sidekiq/version'
require 'sidekiq/util'
require 'sidekiq/client'
require 'sidekiq/manager'
require 'connection_pool'

module Sidekiq
  class CLI
    include Util

    def initialize
      parse_options
      validate!
      boot_rails
    end

    FOREVER = 2_000_000_000

    def run
      ::Sidekiq::Client.redis = ConnectionPool.new { Redis.connect(:url => @options[:server]) }
      manager = Sidekiq::Manager.new(@options[:server], @options)
      begin
        log 'Starting processing, hit Ctrl-C to stop'
        manager.start!
        sleep FOREVER
      rescue Interrupt
        log 'Shutting down...'
        manager.stop!
        manager.wait(:shutdown)
      end
    end

    private

    def boot_rails
      ENV['RAILS_ENV'] = @options[:environment]
      require File.expand_path("#{@options[:rails]}/config/environment.rb")
      ::Rails.application.eager_load!
    end

    def validate!
      $DEBUG = @options[:verbose]

      if !File.exist?("#{@options[:rails]}/config/boot.rb")
        log "========== Please point sidekiq to a Rails 3 application =========="
        log @parser
        exit(1)
      end
    end

    def parse_options(argv=ARGV)
      @options = {
        :verbose => false,
        :queues => ['default'],
        :processor_count => 25,
        :server => ENV['REDISTOGO_URL'] || 'redis://localhost:6379/0',
        :rails => '.',
        :environment => 'production',
      }

      @parser = OptionParser.new do |o|
        o.on "-q", "--queue QUEUE,WEIGHT", "Queue to process, with optional weight" do |arg|
          (q, weight) = arg.split(",")
          (weight || 1).times do
            @options[:queues] << q
          end
        end

        o.on "-v", "--verbose", "Print more verbose output" do
          @options[:verbose] = true
        end

        o.on "-s", "--server LOCATION", "Where to find Redis" do |arg|
          @options[:server] = arg
        end

        o.on '-e', '--environment ENV', "Rails application environment" do |arg|
          @options[:environment] = arg
        end

        o.on '-r', '--rails PATH', "Location of Rails application with workers" do |arg|
          @options[:rails] = arg
        end

        o.on '-c', '--concurrency INT', "processor threads to use" do |arg|
          @options[:processor_count] = arg.to_i
        end
      end

      @parser.banner = "sidekiq [options]"
      @parser.on_tail "-h", "--help", "Show help" do
        log @parser
        exit 1
      end
      @parser.parse!(argv)
    end

  end
end

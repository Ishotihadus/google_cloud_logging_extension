# frozen_string_literal: true

require 'google/cloud/logging'

module Google
  module Cloud
    module Logging
      module Convert
        class << self
          # @param [Exception] exception
          def exception_to_hash(exception, root: false)
            hash = {
              class: exception.class.name,
              message: exception.full_message(highlight: false),
              summary: exception.message,
              backtrace: exception.backtrace,
              cause: exception.cause.is_a?(Exception) ? exception_to_hash(exception.cause) : exception.cause
            }
            hash['@type'] = 'type.googleapis.com/google.devtools.clouderrorreporting.v1beta1.ReportedErrorEvent' if root
            hash
          end

          alias object_to_value_default object_to_value
          def object_to_value(obj)
            if obj.is_a?(Exception)
              return Google::Protobuf::Value.new(struct_value: hash_to_struct(exception_to_hash(obj)))
            end
            return Google::Protobuf::Value.new(struct_value: hash_to_struct(obj.to_hash)) if obj.respond_to?(:to_hash)
            return Google::Protobuf::Value.new(list_value: array_to_list(obj.to_ary)) if obj.respond_to?(:to_ary)

            object_to_value_default(obj)
          end
        end
      end

      DEFAULT_REDIRECTS = []

      def self.create(log_name, resource_type = 'gce_project', **labels)
        logging = Google::Cloud::Logging.new
        writer = logging.async_writer(max_queue_size: 1000)
        resource = logging.resource(resource_type)
        if labels.key?(:level)
          level = labels[:level]
          labels.delete(:level)
        end
        if labels.key?(:redirects)
          redirects = labels[:redirects]
          labels.delete(:redirects)
          redirects = [redirects] unless redirects.is_a?(Array)
          redirects.compact!
        end
        unless DEFAULT_REDIRECTS.empty?
          if redirects
            redirects += DEFAULT_REDIRECTS
          else
            redirects = DEFAULT_REDIRECTS.dup
          end
        end

        logger = Google::Cloud::Logging::Logger.new(writer, log_name, resource, labels)
        logger.level = level if level

        if redirects
          redirects.map! do |e|
            case e
            when :stdout
              ::Logger.new($stdout, progname: labels[:module] || log_name, level: logger.level)
            when :stderr
              ::Logger.new($stderr, progname: labels[:module] || log_name, level: logger.level)
            else
              e
            end
          end

          logger.instance_variable_set(:@redirects, redirects)
        end

        logger
      end

      class Logger
        alias add_default add
        def add(severity, message = nil, progname = nil)
          derived_severity = derive_severity(severity) || ::Logger::UNKNOWN
          @redirects&.each {|e| e.add(derived_severity, message, progname)}
          add_default(severity, message, progname)
        end
      end

      class Entry
        def payload=(payload)
          @payload = case payload
                     when Exception
                       Google::Cloud::Logging::Convert.exception_to_hash(payload, root: true)
                     else
                       payload
                     end
        end
      end
    end
  end
end

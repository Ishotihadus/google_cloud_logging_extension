# frozen_string_literal: true

module Google
  module Cloud
    module Logging
      def self.create(log_name, resource_type = 'gce_project', **labels)
        logging = Google::Cloud::Logging.new
        writer = logging.async_writer(max_queue_size: 1000)
        resource = logging.resource(resource_type)
        if labels.key?(:level)
          level = labels[:level]
          labels.delete(:level)
        end
        logger = Google::Cloud::Logging::Logger.new(writer, log_name, resource, labels)
        logger.level = level if level
        logger
      end

      class Entry
        # @param [Exception] exception
        def create_exception_payload(exception)
          {
            class: exception.class.name,
            message: exception.message,
            backtrace: exception.backtrace,
            cause: exception.cause.is_a?(Exception) ? create_exception_payload(exception.cause) : exception
          }
        end

        def payload=(payload)
          @payload = case payload
                     when Exception
                       create_exception_payload(payload)
                     else
                       payload
                     end
        end
      end
    end
  end
end

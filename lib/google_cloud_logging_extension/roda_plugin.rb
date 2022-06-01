# frozen-string-literal: true

require 'google/cloud/logging'

module Google
  module Cloud
    module Logging
      class Logger
        def write_entry_with_http_request(severity, message, http_request)
          entry = Entry.new.tap do |e|
            e.timestamp = Time.now
            e.severity = gcloud_severity severity
            e.payload = message
          end
          entry.instance_variable_set(:@http_request, http_request)

          actual_log_name = log_name
          info = request_info
          if info
            actual_log_name = info.log_name || actual_log_name
            entry.trace = "projects/#{@project}/traces/#{info.trace_id}" unless info.trace_id.nil? || @project.nil?
            entry.trace_sampled = info.trace_sampled if entry.trace_sampled.nil?
          end

          writer.write_entries entry, log_name: actual_log_name, resource:, labels: entry_labels(info)
        end
      end

      class Entry
        class HttpRequest
          attr_accessor :server_ip, :latency, :protocol

          def to_grpc
            return nil if empty?

            Google::Cloud::Logging::Type::HttpRequest.new(
              request_method: request_method.to_s,
              request_url: url.to_s,
              request_size: size.to_i,
              status: status.to_i,
              response_size: response_size.to_i,
              user_agent: user_agent.to_s,
              remote_ip: remote_ip.to_s,
              referer: referer.to_s,
              server_ip: server_ip.to_s,
              latency:,
              protocol: protocol.to_s,
              cache_hit: !(!cache_hit),
              cache_validated_with_origin_server: !(!validated)
            )
          end
        end
      end
    end
  end
end

class Roda
  module RodaPlugins
    module GoogleCloudLogging
      def self.configure(app, opts = {})
        if opts[:writer].nil? && opts[:resource].nil?
          logging = Google::Cloud::Logging.new
          opts[:writer] = logging.async_writer(max_queue_size: opts[:max_queue_size] || 1000)
          opts[:resource] = logging.resource(opts[:resource_id] || 'gce_project')
        end
        opts[:log_name] ||= 'roda'
        logger = Google::Cloud::Logging::Logger.new(opts[:writer], opts[:log_name], opts[:resource], opts[:labels])
        logger.level = opts[:level] if opts[:level]
        app.opts[:google_cloud_logger] = logger
      end

      module InstanceMethods
        def cloud_logging_set_payload(key, value)
          @google_cloud_logging_custom_payload ||= {}
          @google_cloud_logging_custom_payload[key] = value
        end

        def cloud_logging_set_severity(value)
          @google_cloud_logging_severity = value
        end

        private

        def _roda_before_00__google_cloud_logging
          return unless Process.const_defined?(:CLOCK_MONOTONIC_RAW)

          @google_cloud_logging_clock = Process.clock_gettime(Process::CLOCK_MONOTONIC_RAW)
        end

        def _roda_after_99__google_cloud_logging(res)
          server_ip = "#{env['SERVER_NAME']}:#{env['SERVER_PORT']}"
          latency = @google_cloud_logging_clock &&
                    (Process.clock_gettime(Process::CLOCK_MONOTONIC_RAW) - @google_cloud_logging_clock)
          latency_fraction = latency - latency.to_i

          latency_duration = Google::Protobuf::Duration.new(seconds: latency.to_i,
                                                            nanos: (latency_fraction * 1000 * 1000 * 1000).to_i)

          http_request = Google::Cloud::Logging::Entry::HttpRequest.new
          http_request.request_method = env['REQUEST_METHOD']
          http_request.url = "#{env['rack.url_scheme']}://#{env['HTTP_HOST'] || server_ip}#{env['REQUEST_URI']}"
          http_request.status = res[0]
          http_request.user_agent = env['HTTP_USER_AGENT']
          http_request.remote_ip = env['HTTP_X_REAL_IP'] || env['REMOTE_ADDR']
          http_request.server_ip = server_ip
          http_request.referer = env['HTTP_REFERER']
          http_request.latency = latency_duration
          http_request.protocol = env['SERVER_PROTOCOL']

          severity = @google_cloud_logging_severity || (res[0] >= 500 ? ::Logger::ERROR : ::Logger::INFO)

          message = "#{env['REQUEST_METHOD']} #{env['REQUEST_URI']} #{env['SERVER_PROTOCOL']}"

          payload = { message: }
          payload.merge!(@google_cloud_logging_custom_payload) if @google_cloud_logging_custom_payload

          opts[:google_cloud_logger]&.write_entry_with_http_request(severity, payload, http_request)
        rescue StandardError
          # pass
        end
      end
    end

    register_plugin(:google_cloud_logging, GoogleCloudLogging)
  end
end

# GoogleCloudLoggingExtension

Extension of google-cloud-logging gem.

This extension provides `Google::Cloud::Logging.create` method.

This gem also converts exceptions into json payload.

## Installation

Install the gem and add to the application's Gemfile by executing:

    $ bundle add google_cloud_logging_extension

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install google_cloud_logging_extension

## Usage

### Use default extension

```ruby
require 'google_cloud_logging_extension'

logger = Google::Cloud::Logging.create('test')
# logger = Google::Cloud::Logging.create('test', 'gce_project', hoge: 'fuga')

logger.info('hoge')

begin
  5 / 0
rescue
  logger.error($!)
end
```

### Use roda plugin

```ruby
require 'google_cloud_logging_extension/roda_plugin'

class App < Roda
  plugin :google_cloud_logging, log_name: 'name', labels: { hoge: 'fuga' }
end
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ishotihadus/google_cloud_logging_extension.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

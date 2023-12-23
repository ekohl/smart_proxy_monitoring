module Proxy::Monitoring::Zabbix
  class Main < ::Proxy::Monitoring::Provider
    include Proxy::Log
    include Proxy::Util

    RESULT_OK = 0
    RESULT_WARNING = 1
    RESULT_CRITICAL = 2
    RESULT_UNKNOWN = 3

    def initialize(queue:, url:, user:, password:, ignore_version: false)
      @queue = queue
      # TODO: logout? put it in a service?
      @zabbix = ZabbixApi.connect(url: url, user: user, password: password, ignore_version: ignore_version)
    end

    def query_host(host)
      result = with_errorhandling("Query #{host}") do
        # selectParentTemplates: ['name']
        @zabbix.hosts.get(host: host)
      end
      host_attributes(host, result)
    end

    def create_host(host, attributes)
      result = with_errorhandling("Create #{host}") do
        data = host_data(host, attributes)
        logger.debug { "Creating host #{host} with #{data.inspect}" }
        @zabbix.hosts.create(**data)
      end
      logger.debug { "Created host #{host}: #{result.inspect}" }
      result.to_json
    rescue ZabbixApi::BaseError => e
      logger.error("Failed to create host #{host}: #{e.error_message}")
      raise
    end

    def update_host(host, attributes)
      result = with_errorhandling("Update #{host}") do
        @zabbix.hosts.update(**host_data(host, attributes), force: true)
      end
      logger.debug { "Updated host #{host}: #{result.inspect}" }
      result.to_json
    end

    def remove_host(host)
      result = with_errorhandling("Remove #{host}") do
        @zabbix.hosts.delete(@zabbix.hosts.get_id(host: host))
      end
      result.to_json
    end

    def remove_downtime_host(host, _author, _comment)
      result = with_errorhandling("Remove downtime from #{host}") do
        # TODO: find maintenance for host
        maintenance_ids = []
        @zabbix.maintenance.delete(maintenance_ids)
      end
      result.to_json
    end

    def set_downtime_host(host, author, comment, start_time, end_time, all_services: nil, **)
      result = with_errorhandling("Set downtime on #{host}") do
        host_id = @zabbix.hosts.get_id(host: host)

        @zabbix.maintenance.create(
          name: comment,
          hostids: [host_id],
          # TODO: format of time? Zabbix wants UNIX timestamps
          active_since: start_time,
          active_till: end_time,
          # TODO: fill this?
          timeperiods: [],
        )
      end
      result.to_json
    end

    def handle_event(event)
      validate_hash(event)

      # TODO: event['type'] ?
      # https://www.zabbix.com/documentation/current/en/manual/api/reference/event/object#event
      # TODO: only event type 0?

      timestamp = clock_to_timestamp(event['clock'])
      result = value_and_severity_to_result(event['value'], event['severity'])

      validate_integer(event['itemid'])
      item = @zabbix.item.get(event['itemid'])

      # TODO: key_ or name?
      service = item['key_']

      # acknowledged / surpressed?

      # TODO: is groups needed?
      # TODO: event['groups']?

      # TODO: event['item_tags'] filter for foreman managed?

      validate_array(event['hosts'])
      event['hosts'].each do |host|
        validate_hash(host)
        host = host['host']
        validate_string(host)

        change = {
          host: host,
          service: service,
          result: result,
          timestamp: timestamp,
        }

        queue.push(change)
      end
    end

    private

    # Convert Zabbix host attributes to Foreman attributes
    # See ForemanMonitoring::HostExtensions#monitoring_attributes
    def host_attributes(host, data)
      {
        ip: nil, # TODO
        ip6: nil, # TODO
        architecture: nil,
        os: nil,
        osfamily: nil,
        virtual: nil,
        provider: nil,
        compute_resource: nil,
        hostgroup: nil,
        organization: nil,
        location: nil,
        comment: nil,
        owner_name: nil,
        environment: nil, # TODO: Only if Puppet
        #templates: data['templates'].map { |template| template['name'] },
      }
    end

    # Convert Foreman host attributes to Zabbix attributes
    def host_data(host, attributes)
      # ignored attributes
      # osfamily
      # virtual
      # compute_resource
      # organization
      # environment (note: Puppet environment, may not be present)

      interfaces = []
      # TODO: empty strings for IPs
      [attributes['ip6'], attributes['ip']].compact.each_with_index do |ip, index|
        interfaces << {
          type: 1, # agent
          main: index == 0 ? 1 : 0,
          useip: host.empty? ? 1 : 0, # TODO: setting?
          ip: ip,
          dns: host,
          port: 10050, # TODO: configurable? parameter?
        }
      end

      group_names = ['foreman-host']
      group_names << attributes['hostgroup'] if attributes['hostgroup']

      groups = group_names.map do |group|
        {
          groupid: @zabbix.hostgroups.get_or_create({ name: group }),
        }
      end

      {
        host: host,
        interfaces: interfaces,
        groups: groups,
        templates: [
          # TODO: find foreman-host template
        ],
        inventory_mode: 0,
        inventory: {
          contact: attributes['owner'],
          notes: attributes['comment'],
          hardware: attributes['provider'],
          hw_arch: attributes['architecture'],
          os: attributes['os'],
          location: attributes['location'],
          # model
        }.compact,
      }
    end

    def severity_to_result(value, severity)
      # https://www.zabbix.com/documentation/current/en/manual/api/reference/event/object#event
      unless value.is_a?(Integer)
        logger.warning("Unknown event value '#{value}' received")
        return RESULT_UNKNOWN
      end

      return RESULT_OK if value == 0

      case severity
      when 0 # not classified
        RESULT_UNKNOWN # TODO: map to warning anyway?
      when 1 # information
        RESULT_OK # TODO: map to warning anyway?
      when 2, 3 # warning, average
        RESULT_WARNING
      when 4, 5 # high, disaster
        RESULT_CRITICAL
      else
        logger.warning("Unknown severity '#{severity}' received")
        RESULT_UNKNOWN
      end
    end

    def clock_to_timestamp(clock)
      # TODO: convert unix timestamp to something?
      raise NotImplemented
    end

    def with_errorhandling(action)
      result = yield
      logger.debug "Monitoring - Action successful: #{action}"

      result
    rescue Errno::ECONNREFUSED
      raise Proxy::Monitoring::ConnectionError, "Zabbix server at #{::Proxy::Monitoring::Icinga2::Plugin.settings.url} is not responding"
    rescue SocketError
      raise Proxy::Monitoring::ConnectionError, "Zabbix server '#{::Proxy::Monitoring::Icinga2::Plugin.settings.url}' is unknown"
    end
  end
end

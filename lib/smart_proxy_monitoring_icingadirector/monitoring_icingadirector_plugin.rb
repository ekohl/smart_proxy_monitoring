module ::Proxy::Monitoring::IcingaDirector
  class Plugin < ::Proxy::Provider
    plugin :monitoring_icingadirector, ::Proxy::Monitoring::VERSION

    default_settings verify_ssl: true
    expose_setting :director_url
    expose_setting :director_user
    capability("config")

    requires :monitoring, ::Proxy::Monitoring::VERSION
    requires :monitoring_icinga2, ::Proxy::Monitoring::VERSION

    load_classes do
      require 'smart_proxy_monitoring_common/monitoring_common'
      require 'smart_proxy_monitoring_icingadirector/monitoring_icingadirector_main'
    end

    load_dependency_injection_wirings do |container_instance, _settings|
      container_instance.dependency :monitoring_provider, lambda { ::Proxy::Monitoring::IcingaDirector::Provider.new }
    end
  end
end

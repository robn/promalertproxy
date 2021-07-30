package Test::PromAlertProxy;

use 5.028;
use strict;
use experimental qw(signatures);

use PromAlertProxy::Logger '$Logger' => { init => {
  ident    => 'promalertproxy',
  to_self  => 1,
  log_pid  => 0,
} };

use Test::PromAlertProxy::Target;
use Test::PromAlertProxy::CrashTarget;

sub now { 1558324375 };

sub prom_alert {
  return {
    startsAt => "2019-05-20T03:52:55Z",
    endsAt   => "2019-05-20T03:55:55Z",
    generatorURL => "https://prometheus.internal/graph?g0.expr=up%7Bjob%3D%22prom_node_exporter%22%7D+%3D%3D+0&g0.tab=1",
    annotations => {
      description => "No response from node_exporter on monitor2 for more than 30s",
      summary     => "Host monitor2 down"
    },
    labels => {
      alertname => "node_exporter",
      dc        => "nyi",
      instance  => "10.202.2.231:9100",
      job       => "prom_node_exporter",
      node      => "monitor2",
      severity  => "critical"
    },
  };
}

sub vo_alert {
  return {
    message_type           => "CRITICAL",
    entity_id              => "51643560a4093dbd754ed3a16b136752dc5af49fca7cf3814b040e734f5bb6b1",
    entity_display_name    => "Host monitor2 down",
    state_message          => "No response from node_exporter on monitor2 for more than 30s",
    state_start_time       => 1558324375,
    "prometheus.alertname" => "node_exporter",
    "prometheus.dc"        => "nyi",
    "prometheus.instance"  => "10.202.2.231:9100",
    "prometheus.job"       => "prom_node_exporter",
    "prometheus.node"      => "monitor2",
    "prometheus.severity"  => "critical",
  };
}

sub pd_alert {
  return {
    payload => {
      summary   => "Host monitor2 down",
      timestamp => "2019-05-20T03:52:55Z",
      source    => "monitor2",
      severity  => "critical",
      component => "prom_node_exporter",
      class     => "node_exporter",
      custom_details => {
        description => "No response from node_exporter on monitor2 for more than 30s",
        "prometheus.alertname" => "node_exporter",
        "prometheus.dc"        => "nyi",
        "prometheus.instance"  => "10.202.2.231:9100",
        "prometheus.job"       => "prom_node_exporter",
        "prometheus.node"      => "monitor2",
        "prometheus.severity"  => "critical",
      },
    },
    routing_key => 'testkey',
    dedup_key   => "51643560a4093dbd754ed3a16b136752dc5af49fca7cf3814b040e734f5bb6b1",
    client      => "Prometheus",
    client_url  => "https://prometheus.internal/graph?g0.expr=up%7Bjob%3D%22prom_node_exporter%22%7D+%3D%3D+0&g0.tab=1",
    event_action => "trigger",
  };
}

sub dispatch_logs ($, $hub, $alert) {
  $Logger->clear_events;
  $hub->dispatch($alert);
  while ($hub->loop->loop_once(0)) {}
  return map { $_->{message} } $Logger->events->@*;
}

1;

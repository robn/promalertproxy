#!/usr/bin/env perl

use warnings;
use strict;

use Test::Lib;
use Test::PromAlertProxy;
use Test::More;
use Test::Deep;
use Test::Time time => Test::PromAlertProxy->now;

use PromAlertProxy;

my $vo_alert = Test::PromAlertProxy->vo_alert;
cmp_deeply(
  PromAlertProxy::VOAlert->from_prom_alert(
    PromAlertProxy::PromAlert->new(
      Test::PromAlertProxy->prom_alert,
    ),
  ),
  all(
    isa("PromAlertProxy::VOAlert"),
    methods(
      message_type        => $vo_alert->{message_type},
      entity_id           => $vo_alert->{entity_id},
      entity_display_name => $vo_alert->{entity_display_name},
      state_message       => $vo_alert->{state_message},
      state_start_time    => $vo_alert->{state_start_time},
      extra_fields => superhashof({
        "prometheus.alertname" => $vo_alert->{"prometheus.alertname"},
        "prometheus.dc"        => $vo_alert->{"prometheus.dc"},
        "prometheus.instance"  => $vo_alert->{"prometheus.instance"},
        "prometheus.job"       => $vo_alert->{"prometheus.job"},
        "prometheus.node"      => $vo_alert->{"prometheus.node"},
        "prometheus.severity"  => $vo_alert->{"prometheus.severity"},
      }),
    ),
  ),
  'converted prom alert to vo alert',
);

done_testing;

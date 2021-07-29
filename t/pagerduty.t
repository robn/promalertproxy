#!/usr/bin/env perl

use 5.028;
use warnings;
use experimental qw(signatures);

use Test::Lib;
use Test::PromAlertProxy;
use Test::More;
use Test::Deep;
use Test::Time time => Test::PromAlertProxy->now;

use PromAlertProxy::Hub;
use PromAlertProxy::Alert;
use PromAlertProxy::Target::PagerDuty;

use Net::Async::HTTP;
use JSON::MaybeXS qw(decode_json);
use HTTP::Response;
use Future;

my $pd_alert;
no warnings 'redefine';
local *Net::Async::HTTP::do_request = sub ($self, %args) {
  $pd_alert = decode_json($args{content});
  return Future->done(HTTP::Response->new(200, 'OK'));
};

my $hub = PromAlertProxy::Hub->new;

my $target = PromAlertProxy::Target::PagerDuty->new(
  hub             => $hub,
  id              => 'pagerduty',
  default         => 1,
  integration_key => 'testkey',
);
$hub->add_target($target);

my %alert_contents = Test::PromAlertProxy->prom_alert->%*;
my $alert = PromAlertProxy::Alert->new(%alert_contents);

my @logs = Test::PromAlertProxy->dispatch_logs($hub, $alert);

cmp_deeply($pd_alert, Test::PromAlertProxy->pd_alert, 'PD alert received')
  or diag explain \@logs;

done_testing;

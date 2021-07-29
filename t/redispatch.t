#!/usr/bin/env perl

use 5.028;
use warnings;
use experimental qw(signatures);

use Test::Lib;
use Test::PromAlertProxy;
use Test::More;
use Test::Time time => Test::PromAlertProxy->now;

use PromAlertProxy::Hub;
use PromAlertProxy::Alert;
use PromAlertProxy::Target::Redispatch;

my $hub = PromAlertProxy::Hub->new;

my $rd_target_1 = PromAlertProxy::Target::Redispatch->new(
  hub     => $hub,
  id      => 'rd1',
  default => 1,
  to      => [qw(test1 test2)],
);
my $rd_target_2 = PromAlertProxy::Target::Redispatch->new(
  hub => $hub,
  id  => 'rd2',
  to  => [qw(rd1)],
);

my $end_target_1 = Test::PromAlertProxy::Target->new(
  hub     => $hub,
  id      => 'test1',
);
my $end_target_2 = Test::PromAlertProxy::Target->new(
  hub     => $hub,
  id      => 'test2',
);

$hub->add_target($rd_target_1);
$hub->add_target($rd_target_2);
$hub->add_target($end_target_1);
$hub->add_target($end_target_2);

{
  my %alert_contents = Test::PromAlertProxy->prom_alert->%*;
  my $alert = PromAlertProxy::Alert->new(%alert_contents);

  my @logs = Test::PromAlertProxy->dispatch_logs($hub, $alert);

  is($end_target_1->received_alerts->@*, 1, 'alert redispatched to target 1')
    or diag explain \@logs;
  is($end_target_2->received_alerts->@*, 1, 'alert redispatched to target 2')
    or diag explain \@logs;

  $end_target_1->clear_received_alerts;
  $end_target_2->clear_received_alerts;
}

{
  my %alert_contents = Test::PromAlertProxy->prom_alert->%*;
  $alert_contents{annotations}{target} = 'rd2';
  my $alert = PromAlertProxy::Alert->new(%alert_contents);

  my @logs = Test::PromAlertProxy->dispatch_logs($hub, $alert);

  is($end_target_1->received_alerts->@*, 0, 'alert not double redispatched to target 1')
    or diag explain \@logs;
  is($end_target_2->received_alerts->@*, 0, 'alert not double redispatched to target 2')
    or diag explain \@logs;

  $end_target_1->clear_received_alerts;
  $end_target_2->clear_received_alerts;
}

done_testing;

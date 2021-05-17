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

my $hub = PromAlertProxy::Hub->new;

my $target1 = Test::PromAlertProxy::Target->new(
  hub     => $hub,
  id      => 'test1',
  default => 1,
);
my $target2 = Test::PromAlertProxy::Target->new(
  hub     => $hub,
  id      => 'test2',
);
my $crashtarget = Test::PromAlertProxy::CrashTarget->new(
  hub => $hub,
  id  => 'crashtest',
);
$hub->add_target($target1);
$hub->add_target($target2);
$hub->add_target($crashtarget);

{
  my %alert_contents = Test::PromAlertProxy->prom_alert->%*;
  my $alert = PromAlertProxy::Alert->new(%alert_contents);
  $hub->dispatch($alert);
  is($target1->received_alerts->@*, 1, 'alert with no target dispatched to default target');
}

{
  my %alert_contents = Test::PromAlertProxy->prom_alert->%*;
  $alert_contents{annotations}{target} = 'test1';
  my $alert = PromAlertProxy::Alert->new(%alert_contents);
  $hub->dispatch($alert);
  is($target1->received_alerts->@*, 2, 'alert with target dispatched to correct target (default)');
}

{
  my %alert_contents = Test::PromAlertProxy->prom_alert->%*;
  $alert_contents{annotations}{target} = 'test2';
  my $alert = PromAlertProxy::Alert->new(%alert_contents);
  $hub->dispatch($alert);
  is($target2->received_alerts->@*, 1, 'alert with target dispatched to correct target (non default)');
}

{
  my %alert_contents = Test::PromAlertProxy->prom_alert->%*;
  $alert_contents{annotations}{target} = 'crashtest';
  my $alert = PromAlertProxy::Alert->new(%alert_contents);
  $hub->dispatch($alert);
  is($target1->received_alerts->@*, 3, 'alert fallback dispatched to target 1');
  is($target2->received_alerts->@*, 2, 'alert fallback dispatched to target 2');
}

done_testing;

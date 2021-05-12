#!/usr/bin/env perl

use 5.028;
use warnings;
use experimental qw(signatures);

use Test::Lib;
use Test::PromAlertProxy;
use Test::More;
use Test::Time time => Test::PromAlertProxy->now;

use PromAlertProxy::Hub;
use PromAlertProxy::Config;
use PromAlertProxy::Alert;

use Path::Tiny;

my $conffile = Path::Tiny->tempfile;
$conffile->spew(<<CONFIG);
[target.test1]
  class = "Test::PromAlertProxy::Target"
  default = 1

[target.test2]
  class = "Test::PromAlertProxy::Target"

[target.crashtest]
  class = "Test::PromAlertProxy::CrashTarget"
CONFIG

my $hub = PromAlertProxy::Hub->new;
PromAlertProxy::Config->new(hub => $hub, filename => "$conffile")->inflate;

{
  my %alert_contents = Test::PromAlertProxy->prom_alert->%*;
  my $alert = PromAlertProxy::Alert->new(%alert_contents);
  $hub->dispatch($alert);
  is($hub->_targets->{'test1'}->received_alerts->@*, 1, 'alert with no target dispatched to default target');
}

{
  my %alert_contents = Test::PromAlertProxy->prom_alert->%*;
  $alert_contents{annotations}{target} = 'test1';
  my $alert = PromAlertProxy::Alert->new(%alert_contents);
  $hub->dispatch($alert);
  is($hub->_targets->{test1}->received_alerts->@*, 2, 'alert with target dispatched to correct target (default)');
}

{
  my %alert_contents = Test::PromAlertProxy->prom_alert->%*;
  $alert_contents{annotations}{target} = 'test2';
  my $alert = PromAlertProxy::Alert->new(%alert_contents);
  $hub->dispatch($alert);
  is($hub->_targets->{test2}->received_alerts->@*, 1, 'alert with target dispatched to correct target (non default)');
}

{
  my %alert_contents = Test::PromAlertProxy->prom_alert->%*;
  $alert_contents{annotations}{target} = 'crashtest';
  my $alert = PromAlertProxy::Alert->new(%alert_contents);
  $hub->dispatch($alert);
  is($hub->_targets->{test1}->received_alerts->@*, 3, 'alert fallback dispatched to target 1');
  is($hub->_targets->{test2}->received_alerts->@*, 2, 'alert fallback dispatched to target 2');
}

done_testing;

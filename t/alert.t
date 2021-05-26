#!/usr/bin/env perl

use 5.028;
use warnings;
use experimental qw(signatures);

use Test::Lib;
use Test::PromAlertProxy;
use Test::More;
use Test::Time;

use Date::Format qw(time2str);
use PromAlertProxy::Alert;

subtest "active alerts" => sub {
  my $now_alert = PromAlertProxy::Alert->new(
    labels       => {},
    annotations  => {},
    startsAt     => time2str("%Y-%m-%dT%H:%M:%S%z", time()),
    endsAt       => time2str("%Y-%m-%dT%H:%M:%S%z", time()+86400),
    generatorURL => '',
  );
  ok($now_alert->is_active, "alert starting now is active");

  my $ancient_past_alert = PromAlertProxy::Alert->new(
    labels       => {},
    annotations  => {},
    startsAt     => time2str("%Y-%m-%dT%H:%M:%S%z", time()-86400),
    endsAt       => time2str("%Y-%m-%dT%H:%M:%S%z", time()-43200),
    generatorURL => '',
  );
  ok($ancient_past_alert->is_resolved, "alert finished long ago is resolved");

  my $just_past_alert = PromAlertProxy::Alert->new(
    labels       => {},
    annotations  => {},
    startsAt     => time2str("%Y-%m-%dT%H:%M:%S%z", time()-86400),
    endsAt       => time2str("%Y-%m-%dT%H:%M:%S%z", time()-30),
    generatorURL => '',
  );
  ok($just_past_alert->is_resolved, "alert just finished is resolved");

  my $recent_past_alert = PromAlertProxy::Alert->new(
    labels       => {},
    annotations  => {},
    startsAt     => time2str("%Y-%m-%dT%H:%M:%S%z", time()-86400),
    endsAt       => time2str("%Y-%m-%dT%H:%M:%S%z", time()-90),
    generatorURL => '',
  );
  ok($recent_past_alert->is_resolved, "alert finished a little while go is resolved");
};

done_testing;

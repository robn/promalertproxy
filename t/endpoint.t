#!/usr/bin/env perl

use 5.028;
use warnings;
use experimental qw(signatures);

use Test::Lib;
use Test::PromAlertProxy;
use Test::More;
use Test::Time time => Test::PromAlertProxy->now;

use Plack::Test;
use HTTP::Request::Common;
use JSON::MaybeXS;

use PromAlertProxy::Hub;

my $hub = PromAlertProxy::Hub->new;

my $target = Test::PromAlertProxy::Target->new(
  hub     => $hub,
  id      => 'test',
  default => 1,
);
$hub->add_target($target);

my $t = Plack::Test->create($hub->_app);

my $res = $t->request(
  POST '/api/v2/alerts',
    'Content-type' => 'application/json',
    Content => encode_json([ Test::PromAlertProxy->prom_alert ]),
);

ok($res->is_success, "prom alert successfully posted");

$hub->loop->loop_once;

is($target->received_alerts->@*, 1, 'alert was dispatched to target');

done_testing;

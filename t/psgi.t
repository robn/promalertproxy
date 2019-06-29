#!/usr/bin/env perl

use warnings;
use strict;

use Test::Lib;
use Test::PromAlertProxy;
use Test::More;
use Test::Deep;
use Test::Time time => Test::PromAlertProxy->now;

use Plack::Test;
use HTTP::Request::Common;
use JSON;

use PromAlertProxy;

my $p = PromAlertProxy->new(
  victorops_api_url => 'http://victorops/alert',
);

my $t = Plack::Test->create($p->psgi);

my $vo_alert;

no warnings 'redefine';
local *HTTP::Tiny::_request = sub {
  my ($self, $method, $url, $args) = @_;

  $vo_alert = decode_json($args->{content});

  return {
    status  => 200,
    reason  => 'OK',
    success => 1,
  };
};

my $res = $t->request(
  POST '/alert',
    'Content-type' => 'application/json',
    Content => encode_json([ Test::PromAlertProxy->prom_alert ]),
);

ok($res->is_success, "prom alert successfully posted");

cmp_deeply(
  $vo_alert,
  Test::PromAlertProxy->vo_alert,
  'recieved proper vo alert',
);

done_testing;

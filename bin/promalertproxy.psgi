#!perl
# PODNAME: promalertproxy.psgi

use 5.020;
use warnings;
use strict;

use lib qw(lib);

use Plack::Builder;
use PromAlertProxy;

my $VICTOROPS_API_URL = $ENV{VICTOROPS_API_URL} // die "E: VICTOROPS_API_URL environment variable not set\n";

my $proxy = PromAlertProxy->new(
  victorops_api_url => $VICTOROPS_API_URL,
);

builder {
  mount '/api/v1/alerts' => $proxy->proxy_app;
  mount '/metrics'       => $proxy->metrics_app;
};

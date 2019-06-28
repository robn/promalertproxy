#!perl
# PODNAME: promalertproxy.psgi

use 5.020;
use warnings;
use strict;

use lib qw(lib);

use PromAlertProxy;

my $VICTOROPS_API_URL = $ENV{VICTOROPS_API_URL} // die "E: VICTOROPS_API_URL environment variable not set\n";

PromAlertProxy->new(
  victorops_api_url => $VICTOROPS_API_URL,
)->psgi;

#!perl
# PODNAME: promalertproxy.psgi

use 5.020;
use warnings;
use strict;

use lib qw(lib);

use PromAlertProxy;;

PromAlertProxy->to_app;

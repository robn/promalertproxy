package PromAlertProxy::Target;

use 5.028;
use Moo::Role;
use experimental qw(signatures);

use Types::Standard qw(Str Bool);
use Type::Utils qw(class_type);

has hub => (
  is       => 'ro',
  isa      => class_type('PromAlertProxy::Hub'),
  required => 1,
);

has id => (
  is       => 'ro',
  isa      => Str,
  required => 1,
);

has is_default => (
  init_arg => 'default',
  is       => 'ro',
  isa      => Bool,
  default  => 0,
);

requires qw(raise);

1;

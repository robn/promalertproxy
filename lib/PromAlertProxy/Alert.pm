package PromAlertProxy::Alert;

use 5.028;
use Moo;
use experimental qw(signatures);

use Types::Standard qw(Str Int HashRef Maybe);
use Type::Params qw(compile);

use Date::Parse;
use Digest::SHA qw(sha256_hex);


# in the alert content proper
has labels => (
  is       => 'ro',
  isa      => HashRef[Str],
  required => 1,
);

has annotations => (
  is       => 'ro',
  isa      => HashRef[Str],
  required => 1,
);

has starts_at => (
  is       => 'ro',
  isa      => Int,
  init_arg => 'startsAt',
  coerce   => sub { int str2time(shift) },
);

has ends_at => (
  is       => 'ro',
  isa      => Int,
  init_arg => 'endsAt',
  coerce   => sub { int str2time(shift) },
);

has generator_url => (
  is       => 'ro',
  isa      => Str,
  init_arg => 'generatorURL',
  required => 1,
);


# these are conveniences derived from the alert content
has key => (
  is      => 'lazy',
  isa     => Str,
  default => sub ($self) {
    sha256_hex(join ':', map { ($_, $self->labels->{$_}) } sort keys $self->labels->%*);
  },
);

has target => (
  is      => 'lazy',
  isa     => Maybe[Str],
  default => sub ($self) { $self->annotations->{target} },
);

has name => (
  is      => 'lazy',
  isa     => Str,
  default => sub ($self) { $self->labels->{alertname} // "[unnamed alert]" },
);

has summary => (
  is      => 'lazy',
  isa     => Str,
  default => sub ($self) { $self->annotations->{summary} // "[no summary]" },
);

has description => (
  is      => 'lazy',
  isa     => Str,
  default => sub ($self) { $self->annotations->{description} // "[no description]" },
);

1;

package PromAlertProxy::Config {

use 5.028;
use Moo;
use experimental qw(signatures);

use Types::Standard qw(Str Int HashRef ArrayRef);
use Type::Utils qw(class_type);

use PromAlertProxy::Logger '$Logger';

use Carp qw(croak);
use TOML qw(from_toml);
use Path::Tiny qw(path);
use Module::Runtime qw(require_module);

has hub => (
  is       => 'ro',
  isa      => class_type('PromAlertProxy::Hub'),
  required => 1,
);

has filename => (
  is       => 'ro',
  isa      => Str,
  required => 1,
);

has _config_raw => (
  is => 'lazy',
  isa => HashRef,
  default => sub ($self) {
    my ($config, $err) = from_toml(path($self->filename)->slurp);
    croak "couldn't parse config file '".$self->filename."': $err" unless $config;
    return $config;
  },
);

has _listen_ip => (
  is  => 'lazy',
  isa => Str, # XXX IPAddress
  default => sub ($self) {
    $self->_config_raw->{server}->{ip};
  },
);

has _listen_port => (
  is  => 'lazy',
  isa => Int, # XXX Port
  default => sub ($self) {
    $self->_config_raw->{server}->{port};
  },
);

has _targets => (
  is => 'lazy',
  isa => ArrayRef[class_type('PromAlertProxy::Config::Target')],
  default => sub ($self) {
    my $config = $self->_config_raw;

    my @targets;
    for my $id (keys $config->{target}->%*) {
      my $target_config = $config->{target}->{$id};

      my $target_class = $target_config->{class};
      eval {
        require_module($target_class);
      };
      if (my $err = $@) {
        $Logger->log_fatal(["couldn't require target module %s: %s", $target_class, $err])
      }

      my $target = PromAlertProxy::Config::Target->new(
        hub     => $self->hub,
        id      => $id,
        class   => $target_config->{class},
        default => $target_config->{default},
        config  => {
          map { $_ => $target_config->{$_} }
            grep { ! m/^(?:id|class|default)$/ }
              keys %$target_config,
        },
      );

      push @targets, $target;
    }

    return \@targets;
  },
);

sub inflate ($self) {
  for my $target ($self->_targets->@*) {
    $target->inflate;
  }

  $self->hub->listen($self->_listen_ip, $self->_listen_port);
}

};

package PromAlertProxy::Config::Target {

use 5.028;
use Moo;
use experimental qw(signatures);

use Types::Standard qw(Str Bool HashRef);
use Type::Utils qw(class_type);

use PromAlertProxy::Logger '$Logger';

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

has class => (
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

has config => (
  is      => 'ro',
  isa     => HashRef,
  default => sub { {} },
);

sub inflate ($self) {
  my $target = eval {
    $self->class->new(
      hub     => $self->hub,
      id      => $self->id,
      default => $self->is_default,
      $self->config->%*,
    );
  };
  if (my $err = $@) {
    $Logger->log_fatal(["couldn't instantiate target module %s (for %s): %s", $self->class, $self->id, $err]);
  }

  $self->hub->add_target($target);
};

};

1;

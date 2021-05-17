package PromAlertProxy::Hub;

# ABSTRACT: Proxy Prometheus alerts to other places

use 5.028;
use Moo;
use experimental qw(signatures);

use Types::Standard qw(CodeRef Object Str Int);
use Type::Utils qw(class_type role_type);
use Type::Params qw(compile);

use IO::Async::Loop;
use Prometheus::Tiny;
use Plack::App::URLMap;
use Net::Async::HTTP::Server::PSGI;
use Net::Async::HTTP;

use PromAlertProxy::Logger '$Logger';
use PromAlertProxy::Endpoint;

has loop => (
  is      => 'ro',
  isa     => class_type('IO::Async::Loop'),
  default => sub { IO::Async::Loop->new },
);

has http => (
  is      => 'lazy',
  isa     => class_type('Net::Async::HTTP'),
  default => sub ($self) {
    my $http = Net::Async::HTTP->new;
    $self->loop->add($http);
    return $http;
  },
);

has _metrics => (
  is      => 'lazy',
  isa     => class_type('Prometheus::Tiny'),
  default => sub ($self) {
    my $prom = Prometheus::Tiny->new;
    $prom->declare('promalertproxy_alerts_received_total',
                   type => 'counter',
                   help => 'Number of alerts received from Prometheus');
    $prom->declare('promalertproxy_alerts_dispatched_total',
                   type => 'counter',
                   help => 'Number of alerts dispatched to targets');
    $prom->declare('promalertproxy_alerts_fallback_dispatched_total',
                   type => 'counter',
                   help => 'Number of alerts fallback dispatched');
    $prom;
  },
);

has _endpoint => (
  is      => 'lazy',
  isa     => class_type('PromAlertProxy::Endpoint'),
  default => sub ($self) {
    return PromAlertProxy::Endpoint->new(hub => $self);
  },
);

has _app => (
  is => 'lazy',
  isa => CodeRef,
  default => sub ($self) {
    my $urlmap = Plack::App::URLMap->new;

    # alerts endpoint is the same for both versions
    $urlmap->map('/api/v1/alerts' => $self->_endpoint->psgi);
    $urlmap->map('/api/v2/alerts' => $self->_endpoint->psgi);

    $urlmap->map('/metrics' => $self->_metrics->psgi);
    return $urlmap->to_app;
  },
);

sub listen ($self, $ip, $port) {
  state $check = compile(Object, Str, Int); # XXX IPAddress, Port
  $check->(@_);

  my $http = Net::Async::HTTP::Server::PSGI->new(app => $self->_app);
  $self->loop->add($http);

  $http->listen(
    addr => {
      family   => 'inet',
      socktype => 'stream',
      ip       => $ip,
      port     => $port,
    },
    on_listen_error => sub ($err, @) {
      $Logger->log_fatal(["couldn't listen on %s:%s: %s", $ip, $port, $err]);
    },
  );

  $Logger->log(["listening on %s:%s", $ip, $port]);
}

has _targets        => ( is => 'rw', default => sub { {} } );
has _default_target => ( is => 'rw' );

sub add_target ($self, $target) {
  state $check = compile(Object, role_type('PromAlertProxy::Target'));
  $check->(@_);

  $self->_targets->{$target->id} = $target;
  $Logger->log(['added target: %s', $target->id]);

  if ($target->is_default) {
    if ($self->_default_target) {
      $Logger->log([
        "can't make '%s' the default target, '%s' is already the default",
        $target->id, $self->_default_target->id,
      ]);
    }
    else {
      $self->_default_target($target);
      $Logger->log(['setting default target: %s', $target->id]);
    }
  }
}

sub dispatch ($self, $alert) {
  state $check = compile(Object, class_type('PromAlertProxy::Alert'));
  $check->(@_);

  my $alert_name = $alert->name;
  local $Logger = $Logger->proxy({ proxy_prefix => "$alert_name: " });

  $Logger->log(["received alert: %s", $alert->summary]);

  $self->_metrics->inc('promalertproxy_alerts_received_total', { name => $alert->name });

  my $use_default = 0;
  my $target_name = $alert->target;
  if (!$target_name || !$self->_targets->{$target_name}) {
    $use_default = 1;
  }

  my $target = $use_default ? $self->_default_target : $self->_targets->{$target_name};
  if ($target) {
    $Logger->log(["dispatching to target '%s'%s", $target->id, $use_default ? " (as default)" : ""]);
    $self->_raise_safe($alert, $target);
    return;
  }

  $Logger->log(["no target or default found, fallback dispatching to all"]);
  $self->_raise_all($alert);
}

sub _raise_safe ($self, $alert, $target) {
  $self->_metrics->inc('promalertproxy_alerts_dispatched_total', { name => $alert->name, target => $target->id });

  my $failed = eval {
    $target->raise($alert);
  };

  if (my $err = $@) {
    $Logger->log(["dispatch to target '%s' crashed: %s", $target->id, $err]);
    $failed = 1;
  }

  if ($failed) {
    $Logger->log(["dispatch to target '%s' failed, fallback dispatching to all", $target->id]);
    $self->_raise_all($alert);
  }
}

sub _raise_all ($self, $alert) {
  $self->_metrics->inc('promalertproxy_alerts_fallback_dispatched_total', { name => $alert->name });

  for my $target (values $self->_targets->%*) {
    $Logger->log(["fallback dispatching to target '%s'", $target->id]);

    my $failed = eval {
      $target->raise($alert);
    };

    if (my $err = $@) {
      $Logger->log(["fallback dispatch to target '%s' crashed: %s", $target->id, $err]);
    }
    elsif ($failed) {
      $Logger->log(["fallback dispatch to target '%s' failed", $target->id]);
    }
  }
}

1;

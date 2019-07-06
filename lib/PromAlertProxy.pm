package PromAlertProxy {

# ABSTRACT: Proxy Prometheus alerts to VictorOps

use 5.020;
use Moo;
use experimental qw(postderef);

use Types::Standard qw(Str);

use Plack::Request;
use Plack::Response;
use JSON::MaybeXS;
use Try::Tiny;
use HTTP::Tiny;
use Prometheus::Tiny::Shared;

has victorops_api_url => (
  is       => 'ro',
  isa      => Str,
  required => ,1
);

has _http => (
  is      => 'lazy',
  default => sub { HTTP::Tiny->new },
);

has _prom => (
  is => 'lazy',
  default => sub {
    my $prom = Prometheus::Tiny::Shared->new;
    $prom->declare('promalertproxy_http_requests_total',
                   type => 'counter',
                   help => 'Number of requests received');
    $prom->declare('promalertproxy_http_bad_requests_total',
                   type => 'counter',
                   help => 'Number of bad requests received');
    $prom->declare('promalertproxy_vo_alert_create_errors_total',
                   type => 'counter',
                   help => 'Number of errors creating VOAlert objects');
    $prom->declare('promalertproxy_victorops_alerts_total',
                   type => 'counter',
                   help => 'Number of alerts posted by Prometheus');
    $prom->declare('promalertproxy_victorops_post_errors_total',
                   type => 'counter',
                   help => 'Number of errors posting alerts to VictorOps');
    $prom;
  },
);

sub metrics_app {
  my ($self) = @_;
  return $self->_prom->psgi;
}

sub proxy_app {
  my ($self) = @_;
  return sub {
    my ($env) = @_;

    my $req = Plack::Request->new($env);

    return Plack::Response->new(405)->finalize unless $req->method eq 'POST';
    return Plack::Response->new(415)->finalize unless $req->content_type eq 'application/json';

    $self->_prom->inc('promalertproxy_http_requests_total');

    my $data = try {
      decode_json($req->content);
    }
    catch {
      warn "failed to parse content: $_\n";
    };
    unless ($data && ref $data eq 'ARRAY') {
      $self->_prom->inc('promalertproxy_http_bad_requests_total', { type => 'json_parse_failed' });
      return Plack::Response->new(400)->finalize
    }

    my $prom_alerts = try {
      [
        map {
          PromAlertProxy::PromAlert->new($_->%*)
        } $data->@*
      ];
    }
    catch {
      warn "failed to create Prometheus alert objects: $_\n";
    };
    unless ($prom_alerts) {
      $self->_prom->inc('promalertproxy_http_bad_requests_total', { type => 'prom_alert_create_failed' });
      return Plack::Response->new(400)->finalize
    }

    my $vo_alerts = try {
      [
        map {
          PromAlertProxy::VOAlert->from_prom_alert($_)
        } $prom_alerts->@*
      ];
    }
    catch {
      warn "failed to create VictorOps alert objects: $_\n";
    };
    unless ($vo_alerts) {
      $self->_prom->inc('promalertproxy_vo_alert_create_errors_total');
      return Plack::Response->new(500)->finalize
    }

    my $http = $self->_http;
    for my $alert ($vo_alerts->@*) {
      $self->_prom->inc('promalertproxy_victorops_alerts_total', { type => $alert->message_type });
      my $res = $http->post($self->victorops_api_url,
        {
          headers => {
            'Content-type' => 'application/json',
          },
          content => $alert->to_json,
        },
      );
      unless ($res->{success}) {
        $self->_prom->inc('promalertproxy_victorops_post_errors_total', { status => $res->{status} });
        warn "error posting alert to VictorOps: $res->{status} $res->{reason}\n"
      }
    }

    return Plack::Response->new(200)->finalize;
  };
}

}

package  # hide from PAUSE
  PromAlertProxy::PromAlert {

use namespace::autoclean;
use Moo;
use Types::Standard qw(Str Int HashRef);

use Date::Parse;

has labels        => ( is => 'ro', isa => HashRef[Str],                             
                        required => 1 );
has annotations   => ( is => 'ro', isa => HashRef[Str],                             
                        required => 1 );
has starts_at     => ( is => 'ro', isa => Int,          
                        init_arg => 'startsAt', coerce => sub { int str2time(shift) } );
has ends_at       => ( is => 'ro', isa => Int,          
                        init_arg => 'endsAt',   coerce => sub { int str2time(shift) } );
has generator_url => ( is => 'ro', isa => Str,
                        init_arg => 'generatorURL', required => 1 );

}

package  # hide from PAUSE
  PromAlertProxy::VOAlert {

use namespace::autoclean;
use Moo;
use Types::Standard qw(Str Enum Int HashRef);
use Digest::SHA qw(sha256_hex);
use JSON::MaybeXS;
use Defined::KV;
use experimental qw(postderef);

has message_type        => ( is => 'ro', isa => Enum[qw(CRITICAL WARNING ACKNOWLEDGEMENT INFO RECOVERY)],
                              required => 1 );
has entity_id           => ( is => 'ro', isa => Str,
                              required => 1 );
has entity_display_name => ( is => 'ro', isa => Str );
has state_message       => ( is => 'ro', isa => Str );
has state_start_time    => ( is => 'ro', isa => Int );
has extra_fields        => ( is => 'ro', isa => HashRef[Str], default => sub { {} } );

sub from_prom_alert {
  my ($class, $alert) = @_;

  my $message_type = uc(($alert->labels->{severity} || 'critical'));
  $message_type = 'CRITICAL' unless $message_type =~ m/^(?:CRITICAL|WARNING|INFO)$/;
  $message_type = 'RECOVERY' if ($alert->ends_at // (time+60)) < time; # arbitrary future

  my $entity_id = sha256_hex(join ':', map { "$_:".$alert->labels->{$_} } sort keys $alert->labels->%*);

  my $entity_display_name = $alert->annotations->{summary};
  my $state_message       = $alert->annotations->{description};

  my $state_start_time = $alert->starts_at;

  my %extra_fields = map { ("prometheus.$_" => $alert->labels->{$_}) } keys $alert->labels->%*;

  PromAlertProxy::VOAlert->new(
    message_type => $message_type,
    entity_id    => $entity_id,
    defined_kv(entity_display_name => $entity_display_name),
    defined_kv(state_message       => $state_message),
    defined_kv(state_start_time    => $state_start_time),
    extra_fields => \%extra_fields,
  );
}

sub to_json { shift->_json };
has _json => ( is => 'lazy', isa => Str );
sub _build__json {
  my ($self) = @_;
  encode_json({
    message_type => $self->message_type,
    entity_id    => $self->entity_id,
    defined_kv(entity_display_name => $self->entity_display_name),
    defined_kv(state_message       => $self->state_message),
    defined_kv(state_start_time    => $self->state_start_time),
    $self->extra_fields->%*,
  });
}

}

1;

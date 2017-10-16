package PromAlertProxy {

# ABSTRACT: Proxy Prometheus alerts to VictorOps

use 5.020;
use warnings;
use strict;
use experimental qw(postderef);

use Plack::Request;
use Plack::Response;
use JSON::MaybeXS;
use Try::Tiny;
use HTTP::Tiny;

my $VICTOROPS_API_URL = $ENV{VICTOROPS_API_URL} // die "E: VICTOROPS_API_URL environment variable not set\n";

my $app = sub {
  my ($env) = @_;

  my $req = Plack::Request->new($env);

  return Plack::Response->new(400)->finalize
    if $req->method ne 'POST'
    or $req->content_type ne 'application/json';

  my $data = try {
    decode_json($req->content);
  }
  catch {
    warn "failed to parse content: $_\n";
  };
  return Plack::Response->new(400)->finalize
    unless $data && ref $data eq 'ARRAY';

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
  return Plack::Response->new(400)->finalize
    unless $prom_alerts;

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
  return Plack::Response->new(500)->finalize
    unless $vo_alerts;

  my $ua = HTTP::Tiny->new;
  for my $alert ($vo_alerts->@*) {
    my $res = $ua->post($VICTOROPS_API_URL,
      {
        headers => {
          'Content-type' => 'application/json',
        },
        content => $alert->to_json,
      },
    );
    warn "error posting alert to VictorOps: $res->{status} $res->{reason}\n"
      unless $res->{success};
  }

  return Plack::Response->new(200)->finalize;
}; 

sub to_app { $app }

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

  my $entity_id = sha256_hex(join ':', map { "$_:$alert->labels->{$_}" } sort keys $alert->labels->%*);

  my $entity_display_name = $alert->annotations->{summary};
  my $state_message       = $alert->annotations->{description};

  my $state_start_time = $alert->starts_at;

  my %extra_fields = map { ("prometheus.$_" => $alert->labels->{$_}) } keys $alert->labels->%*;

  PromAlertProxy::VOAlert->new(
    message_type => $message_type,
    entity_id    => $entity_id,
    ($entity_display_name ? (entity_display_name => $entity_display_name) : ()),
    ($state_message       ? (state_message       => $state_message      ) : ()),
    ($state_start_time    ? (state_start_time    => $state_start_time   ) : ()),
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
    ($self->entity_display_name ? (entity_display_name => $self->entity_display_name) : ()),
    ($self->state_message       ? (state_message       => $self->state_message      ) : ()),
    ($self->state_start_time    ? (state_start_time    => $self->state_start_time   ) : ()),
    $self->extra_fields->%*,
  });
}

}

1;

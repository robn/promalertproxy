package PromAlertProxy::Target::VictorOps;

use 5.028;
use Moo;
use experimental qw(signatures);

with 'PromAlertProxy::Target';

use Types::Standard qw(Str Object);
use Type::Utils qw(class_type);
use Type::Params qw(compile);

use JSON::MaybeXS qw(encode_json);

use PromAlertProxy::Logger '$Logger';

has api_url => (
  is       => 'ro',
  isa      => Str,
  required => 1,
);

has integration_key => (
  is       => 'ro',
  isa      => Str,
  required => 1,
);

sub raise ($self, $alert) {
  state $check = compile(Object, class_type('PromAlertProxy::Alert'));
  $check->(@_);

  my $event_action;
  my $severity;

  if ($alert->is_resolved) {
    $event_action = 'resolve';
    $severity = 'info'
  }
  else {
    $event_action = 'trigger';
    $severity = uc(($alert->labels->{severity} || 'critical'));
    $severity = 'critical' unless $severity =~ m/^(?:critical|error|warning|info)$/;
  }

  my %extra_fields = map { ("prometheus.$_" => $alert->labels->{$_}) } keys $alert->labels->%*;

  my %payload = (
    routing_key         => $self->routing_key,
    event_action        => $event_action,
    severity            => $severity,
    dedup_key           => $alert->key,
    "payload.summary"   => $alert->summary,
    "payload.source"    => $alert->node,
    state_message       => $alert->description,
    "payload.timestamp" => $alert->starts_at,
    %extra_fields,
  );

  my ($res) = $self->hub->http->do_request(
    uri          => $self->api_url,
    method       => 'POST',
    content_type => 'application/json',
    content      => encode_json(\%payload),
  )->get;

  return if $res->is_success;

  $Logger->log(["POST to PagerDuty failed: %s", $res->status_line]);
  return 1;
}

1;

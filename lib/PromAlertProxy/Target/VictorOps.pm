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
  isa      => Str, # XXX URL
  required => 1,
);

sub raise ($self, $alert) {
  state $check = compile(Object, class_type('PromAlertProxy::Alert'));
  $check->(@_);

  my $message_type = uc(($alert->labels->{severity} || 'critical'));
  $message_type = 'CRITICAL' unless $message_type =~ m/^(?:CRITICAL|WARNING|INFO)$/;
  $message_type = 'RECOVERY' if ($alert->ends_at // (time+60)) < time; # arbitrary future

  my %extra_fields = map { ("prometheus.$_" => $alert->labels->{$_}) } keys $alert->labels->%*;

  my %payload = (
    message_type        => $message_type,
    entity_id           => $alert->key,
    entity_display_name => $alert->summary,
    state_message       => $alert->description,
    state_start_time    => $alert->starts_at,
    %extra_fields,
  );

  my ($res) = $self->hub->http->do_request(
    uri          => $self->api_url,
    method       => 'POST',
    content_type => 'application/json',
    content      => encode_json(\%payload),
  )->get;

  return if $res->is_success;

  $Logger->log(["POST to VictorOps failed: %s", $res->status_line]);
  return 1;
}

1;

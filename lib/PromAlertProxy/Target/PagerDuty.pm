package PromAlertProxy::Target::PagerDuty;

use 5.028;
use Moo;
use experimental qw(signatures);

with 'PromAlertProxy::Target';

use Types::Standard qw(Str Object);
use Type::Utils qw(class_type);
use Type::Params qw(compile);

use JSON::MaybeXS qw(encode_json);
use Date::Format qw(time2str);
use Defined::KV;

use PromAlertProxy::Logger '$Logger';

has integration_url => (
  is       => 'ro',
  isa      => Str, # XXX URL
  default  => 'https://events.pagerduty.com/v2/enqueue',
);

has integration_key => (
  is       => 'ro',
  isa      => Str,
  required => 1,
);


sub raise ($self, $alert) {
  state $check = compile(Object, class_type('PromAlertProxy::Alert'));
  $check->(@_);

  my %alert = (
    routing_key => $self->integration_key,
    dedup_key   => $alert->key,
  );

  if ($alert->is_resolved) {
    $alert{event_action} = 'resolve';
  }

  else {
    my $severity = $alert->labels->{severity} || 'critical';
    $severity = 'critical' unless $severity =~ m/^(?:critical|error|warning|info)$/;

    my $labels = $alert->labels;
    my %custom_details = map { ("prometheus.$_" => $labels->{$_}) } keys %$labels;

    $alert{payload} = {
      summary   => $alert->summary,
      timestamp => time2str('%Y-%m-%dT%XZ', $alert->starts_at, 'UTC'),
      source    => $labels->{node} // 'unknown',
      severity  => $severity,
      defined_kv(component => $labels->{job}),
      defined_kv(class     => $labels->{alertname}),
      custom_details => {
        description => $alert->description,
        %custom_details,
      },
    };

    $alert{client}     = 'Prometheus';
    $alert{client_url} = $alert->generator_url;

    $alert{event_action} = 'trigger';
  }

  my ($res) = $self->hub->http->do_request(
    uri          => $self->integration_url,
    method       => 'POST',
    content_type => 'application/json',
    content      => encode_json(\%alert),
  )->get;

  return if $res->is_success;

  $Logger->log(["POST to PagerDuty failed: %s", $res->status_line]);
  return 1;
}

1;

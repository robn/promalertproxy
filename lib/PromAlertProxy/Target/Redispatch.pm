package PromAlertProxy::Target::Redispatch;

use 5.028;
use Moo;
use experimental qw(signatures);

with 'PromAlertProxy::Target';

use Types::Standard qw(Str Object ArrayRef);
use Type::Utils qw(class_type);
use Type::Params qw(compile);

use PromAlertProxy::Logger '$Logger';

has to => (
  is       => 'ro',
  isa      => ArrayRef[Str],
  required => 1,
);

sub raise ($self, $alert) {
  state $check = compile(Object, class_type('PromAlertProxy::Alert'));
  $check->(@_);

  if ($alert->was_redispatched) {
    $Logger->log(["cannot redispatch a redispatched alert!"]);
    return;
  }

  for my $to ($self->to->@*) {
    $Logger->log(["redispatch to: %s", $to]);

    my $new_alert = $alert->clone_for_redispatch($to);
    $self->hub->loop->later(sub {
      $self->hub->dispatch($new_alert);
    });
  }

  return;
}

1;

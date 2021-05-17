package Test::PromAlertProxy::Target;

use 5.028;
use Moo;
use experimental qw(signatures);

with 'PromAlertProxy::Target';

use Types::Standard qw(Object ArrayRef);
use Type::Utils qw(class_type);
use Type::Params qw(compile);

has received_alerts => (
  is      => 'ro',
  isa     => ArrayRef,
  default => sub { [] },
);

sub raise ($self, $alert) {
  state $check = compile(Object, class_type('PromAlertProxy::Alert'));
  $check->(@_);

  push $self->received_alerts->@*, $alert;

  return;
}

1;

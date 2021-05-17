package Test::PromAlertProxy::CrashTarget;

use 5.028;
use Moo;
use experimental qw(signatures);

with 'PromAlertProxy::Target';

use Types::Standard qw(Object ArrayRef);
use Type::Utils qw(class_type);
use Type::Params qw(compile);

sub raise ($self, $alert) {
  state $check = compile(Object, class_type('PromAlertProxy::Alert'));
  $check->(@_);

  die "oh no";
}

1;

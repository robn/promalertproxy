package PromAlertProxy::Target::Email;

use 5.028;
use Moo;
use experimental qw(signatures);

with 'PromAlertProxy::Target';

use Types::Standard qw(Object Str HashRef Int);
use Type::Utils qw(role_type class_type);
use Type::Params qw(compile);

use Module::Runtime qw(require_module);

use Email::Stuffer;
use Template::Tiny;

use PromAlertProxy::Logger '$Logger';

has from => (
  is       => 'ro',
  isa      => Str, # XXX EmailAddress
  required => 1,
);

has to => (
  is       => 'ro',
  isa      => Str, # XXX EmailAddress
  required => 1,
);

has transport_class => (
  is       => 'ro',
  isa      => Str,
  required => 1,
  trigger  => sub ($self, $val) { require_module($val) }
);

has transport_args => (
  is      => 'ro',
  isa     => HashRef,
  default => sub { {} },
);

has headers => (
  is      => 'ro',
  isa     => HashRef,
  coerce  => sub ($config) {
    +{ map { delete ($_->{header}) => $_ } @$config },
  },
  default => sub { [] },
);

has _transport => (
  is      => 'lazy',
  isa     => role_type('Email::Sender::Transport'),
  default => sub ($self) {
    $self->transport_class->new($self->transport_args);
  },
);

has suppress_interval => (
  is      => 'ro',
  isa     => Int,
  default => 60*60,
);

has _seen => (
  is => 'ro',
  isa => HashRef,
  default => sub { {} },
);

sub raise ($self, $alert) {
  state $check = compile(Object, class_type('PromAlertProxy::Alert'));
  $check->(@_);

  if ($alert->is_active) {
    my $now_ts = time;
    my $first_ts = $self->_seen->{$alert->key} // 0;
    if ($first_ts + $self->suppress_interval > $now_ts) {
      $Logger->log(["alert key %s seen too recently (%d seconds ago), dropping it", $alert->key, $now_ts - $first_ts]);
      return;
    }
    $self->_seen->{$alert->key} = $now_ts;
  }
  else {
    delete $self->_seen->{$alert->key};
  }

  my %headers;
  for my $header (keys $self->headers->%*) {
    my $spec = $self->headers->{$header};
    if (my $value = $spec->{value}) {
      $headers{$header} = $value;
    }
    elsif (my $label = $spec->{label}) {
      if (my $value = $alert->labels->{$label}) {
        $headers{$header} = $value;
      }
    }
  }

  my $prefix = 
    $alert->is_active ? "\N{POLICE CARS REVOLVING LIGHT} ALERT"
                      : "\N{WHITE HEAVY CHECK MARK} RESOLVED";

  my $stuffer = Email::Stuffer->from($self->from)
                              ->to($self->to)
                              ->subject($prefix.': '.$alert->name.': '.$alert->summary)
                              ->text_body($self->_body_for($alert))
                              ->header('In-Reply-To' => '<'.$alert->key.'@promalertproxy>')
                              ->transport($self->_transport);

  $stuffer->header($_ => $headers{$_}) for keys %headers;

  $stuffer->send_or_die;

  return;
}

sub _body_for ($self, $alert) {
  state $template = do { local $/; <DATA> };

  my $output;
  Template::Tiny->new->process(\$template, {
    key              => $alert->key,
    name             => $alert->name,
    summary          => $alert->summary,
    description      => $alert->description,
    labels           => $alert->labels,
    annotations      => $alert->annotations,
    dump_labels      =>
      do { my $d = $alert->labels; join("\n", map { "$_: $d->{$_}" } sort keys %$d) },
    dump_annotations =>
      do { my $d = $alert->annotations; join("\n", map { "$_: $d->{$_}" } sort keys %$d) },
  }, \$output);

  return $output;
}

1;

__DATA__

[% name %]: [% summary %]

[% description %]

labels:
[% dump_labels %]

annotations:
[% dump_annotations %]


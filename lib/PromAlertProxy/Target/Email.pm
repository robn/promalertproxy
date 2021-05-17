package PromAlertProxy::Target::Email;

use 5.028;
use Moo;
use experimental qw(signatures);

with 'PromAlertProxy::Target';

use Types::Standard qw(Object Str HashRef);
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

has _transport => (
  is      => 'lazy',
  isa     => role_type('Email::Sender::Transport'),
  default => sub ($self) {
    $self->transport_class->new($self->transport_args);
  },
);

sub raise ($self, $alert) {
  state $check = compile(Object, class_type('PromAlertProxy::Alert'));
  $check->(@_);

  Email::Stuffer->from($self->from)
                ->to($self->to)
                ->subject($alert->name.': '.$alert->summary)
                ->text_body($self->_body_for($alert))
                ->header('In-Reply-To' => '<'.$alert->key.'@promalertproxy>')
                ->transport($self->_transport)
                ->send_or_die;

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


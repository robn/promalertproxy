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

  # once an alert stops firing, we will remember its key forever. I'm not doing
  # anything about that, because it should be a negligible amount of memory. in
  # the future though, maybe we could have a timer on it -- robn, 2022-02-02 

  my $now_ts = time;

  my $seen = $self->_seen->{$alert->key};

  my $should_fire =                                      # send email if:
    !$seen ||                                            # - never saw it before
    $seen->{ts} + $self->suppress_interval <= $now_ts || # - last saw it a long time ago
    $seen->{active} ^ $alert->is_active;                 # - state changed since we last saw it

  unless ($should_fire) {
    $Logger->log(["alert seen too recently (%d seconds ago), dropping it", $now_ts - $seen->{ts}]);
    return;
  }

  $self->_seen->{$alert->key} = { ts => $now_ts, active => $alert->is_active };

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


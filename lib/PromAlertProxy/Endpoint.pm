package PromAlertProxy::Endpoint;

use 5.028;
use Moo;
use experimental qw(signatures);

use Types::Standard qw(CodeRef);
use Type::Utils qw(class_type);

use Plack::Request;
use Plack::Response;
use JSON::MaybeXS qw(decode_json);

use PromAlertProxy::Logger '$Logger';
use PromAlertProxy::Alert;

has hub => (
  is       => 'ro',
  isa      => class_type('PromAlertProxy::Hub'),
  required => 1,
  weak_ref => 1, # Hub has an Endpoint
);

has psgi => (
  is => 'lazy',
  isa => CodeRef,
);

sub _build_psgi ($self) {
  return sub ($env, @) {
    my $req = Plack::Request->new($env);

    return Plack::Response->new(405)->finalize
      unless $req->method eq 'POST';
    return Plack::Response->new(415)->finalize
      unless $req->content_type eq 'application/json';

    my $data = eval {
      decode_json($req->content);
    };
    if (my $err = $@) {
      $Logger->log(["incoming alert parse failed: %s", $err]);
    }

    return Plack::Response->new(400)->finalize
      unless $data && ref $data eq 'ARRAY';

    my @alerts;
    for my $single ($data->@*) {
      my $alert = eval {
        PromAlertProxy::Alert->new($single->%*);
      };
      if (my $err = $@) {
        $Logger->log(["failed to create alert object: %s", $err]);
        next;
      }

      push @alerts, $alert;
    }

    return Plack::Response->new(500)->finalize
      if (!@alerts && $data->@*);

    for my $alert (@alerts) {
      $self->hub->loop->later(sub {
        $self->hub->dispatch($alert);
      });
    }

    return Plack::Response->new(200)->finalize;
  };
}


1;

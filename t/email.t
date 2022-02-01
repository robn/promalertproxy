#!/usr/bin/env perl

use 5.028;
use warnings;
use experimental qw(signatures);

use Test::Lib;
use Test::PromAlertProxy;
use Test::More;
use Test::Deep;
use Test::Time time => Test::PromAlertProxy->now;

use PromAlertProxy::Hub;
use PromAlertProxy::Alert;
use PromAlertProxy::Target::Email;

my $hub = PromAlertProxy::Hub->new;

my $target = PromAlertProxy::Target::Email->new(
  hub             => $hub,
  id              => 'email',
  default         => 1,
  from            => 'from@localhost',
  to              => 'to@localhost',
  transport_class => 'Email::Sender::Transport::Test',
);
$hub->add_target($target);

my %alert_contents = Test::PromAlertProxy->prom_alert->%*;

my $mail_transport = $target->_transport;

{
  my $alert = PromAlertProxy::Alert->new(%alert_contents);
  my @logs = Test::PromAlertProxy->dispatch_logs($hub, $alert);

  is($mail_transport->delivery_count, 1, 'email alert receieved')
    or diag explain \@logs;

  if (my $email = $mail_transport->shift_deliveries) {
    my $summary = $alert->summary;
    my $subject = $email->{email}->get_header('Subject');
    like($subject, qr/ALERT/, 'alert email says ALERT');
    like($subject, qr/$summary/, 'email content probably fine');
  }

  $mail_transport->clear_deliveries;
}

{
  my $alert = PromAlertProxy::Alert->new(%alert_contents);
  my @logs = Test::PromAlertProxy->dispatch_logs($hub, $alert);

  is($mail_transport->delivery_count, 0, 'email alert suppressed')
    or diag explain \@logs;
}

sleep $target->suppress_interval * 2;

{
  my $alert = PromAlertProxy::Alert->new(%alert_contents);
  my @logs = Test::PromAlertProxy->dispatch_logs($hub, $alert);
  is($mail_transport->delivery_count, 1, 'previously suppressed email alert received')
    or diag explain \@logs;

  if (my $email = $mail_transport->shift_deliveries) {
    my $summary = $alert->summary;
    my $subject = $email->{email}->get_header('Subject');
    like($subject, qr/RESOLVED/, 'resolved email says RESOLVED');
    like($subject, qr/$summary/, 'email content probably fine');
  }
}

done_testing;

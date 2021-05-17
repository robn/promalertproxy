package PromAlertProxy::Logger;

use strict;
use warnings;
use parent 'Log::Dispatchouli::Global';

use Log::Dispatchouli 2.002;

sub logger_globref {
  no warnings 'once';
  \*Logger;
}

sub default_logger_class { 'PromAlertProxy::Logger::_Logger' }

sub default_logger_args {
  return {
    ident     => "promalertproxy",
    facility  => 'daemon',
    to_stderr => $_[0]->default_logger_class->env_value('STDERR') ? 1 : 0,
    to_file   => $_[0]->default_logger_class->env_value('FILE') ? 1 : 0,
  }
}

{
  package
    PromAlertProxy::Logger::_Logger;
  use parent 'Log::Dispatchouli';

  sub env_prefix { 'PROMALERTPROXY_LOG' }
}

1;

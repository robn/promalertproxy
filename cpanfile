requires "Date::Parse" => "0";
requires "Defined::KV" => "0";
requires "Digest::SHA" => "0";
requires "HTTP::Tiny" => "0";
requires "JSON::MaybeXS" => "0";
requires "Moo" => "0";
requires "Plack::Request" => "0";
requires "Plack::Response" => "0";
requires "Try::Tiny" => "0";
requires "Types::Standard" => "0";
requires "experimental" => "0";
requires "lib" => "0";
requires "namespace::autoclean" => "0";
requires "perl" => "5.020";
requires "strict" => "0";
requires "warnings" => "0";

on 'configure' => sub {
  requires "ExtUtils::MakeMaker" => "0";
};

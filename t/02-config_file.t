#!perl -T

use Test::More tests => 7;
use Config::Std; # Uses read_config to pull info from a config files. enhanced INI format.

my $config_file = 'test_config.cfg';


my %config_file_hash;
ok((read_config $config_file => %config_file_hash), "Load config file");

my @values = qw(server port conference username password test_forum );
foreach my $value (@values) {
    ok(defined($config_file_hash{main}{$value}), "$value set in file");
    BAIL_OUT("$value set in file") if(!defined $config_file_hash{main}{$value});
}

#!perl -T

use Test::More tests => 9;
use Config::Std; # Uses read_config to pull info from a config files. enhanced INI format.
use Net::Jabber::Bot;
#use Log::Log4perl qw(:easy);

# Load config file.
my $config_file = 'test_config.cfg';
my %config_file_hash;
ok((read_config $config_file => %config_file_hash), "Load config file");

my $alias = 'make_test_bot';
my $loop_sleep_time = 5;
my $server_info_timeout = 5;
my @forums_to_join;
push @forums_to_join, $config_file_hash{'main'}{'test_forum'};
my @responses = ('', 'tbot:');

my $bot = Net::Jabber::Bot->new({
    server => $config_file_hash{'main'}{'server'}
    , conference_server => $config_file_hash{'main'}{'conference'}
    , port => $config_file_hash{'main'}{'port'}
    , username => $config_file_hash{'main'}{'username'}
    , password => $config_file_hash{'main'}{'password'}
    , alias => $alias
    , forums => \@forums_to_join
});

ok(defined $bot, "Bot initialized and connected");

ok(defined $bot->Process(), "Bot connected to server");

# Now check if the privates can be called
$bot->Disconnect();

my @privates = qw(CreateJabberNamespaces InitJabber SendJabberMessage _SendIndividualMessage _get_obj_id _which_object_am_i);

foreach $private_module (@privates) {
    my $call = "\$bot->$private_module()";
    eval $call;
    ok($@ =~ m/Can\'t call private method /, "Verify private sub $call can not be executed outside class"); # Expect this subroutine to fail...
}

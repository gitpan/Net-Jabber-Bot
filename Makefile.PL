use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Net::Jabber::Bot',
    AUTHOR              => 'Todd E Rinaldo <todd.e.rinaldo@jpmorgan.com>',
    VERSION_FROM        => 'lib/Net/Jabber/Bot.pm',
    ABSTRACT_FROM       => 'lib/Net/Jabber/Bot.pm',
    PL_FILES            => {},
    PREREQ_PM => {
        'Class::Std' => 0,  # For testing
        'Test::More' => 0,  # For testing
        'Config::Std' => 0, # Used by test modules
        'IO::Prompt' => 0,  # Used test to extract config values. May be a little heavy to have just for test?
        'Net::Jabber' => 2.0,  # The whole thing is based on Net::Jabber. 
        'Log::Log4perl' => 0,  # We use log4perl. not sure how bad this'll screw people over... should consider removal later or make it optional
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Net-Jabber-Bot-*' },
);

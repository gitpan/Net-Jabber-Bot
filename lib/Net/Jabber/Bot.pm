package Net::Jabber::Bot;

use strict;
use warnings;

use version; 

use Net::Jabber;
use Time::HiRes;
use Log::Log4perl qw(:easy);

use Class::Std;

my %jabber_client   : ATTR; # Keep track of the jabber object we're using.
my %connection_hash : ATTR; # Keep track of connection options fed to client.
my %connection_session_id : ATTR; # Reverse hash where we'll figure out what object we are...
my %self_from_ident : ATTR; # Since I don't know how to ask Class::Std, I'm just trapping it in BUILD.
my %message_function : ATTR; # What is called if we are fed a new message once we're logged in.
my %bot_background_activity : ATTR; # What is called if we are fed a new message once we're logged in.
my %forum_join_time : ATTR; # Tells us if we've parsed historical messages yet.
my %client_start_time :ATTR; # Track when we came online.
my %process_timeout : ATTR; # Time to take in process loop if no messages found/
my %loop_sleep_time : ATTR; # Time to sleep each time we go through a Start() loop.
my %ignore_messages : ATTR; #Messages to ignore if we recieve them.
my %aliases_to_respond_to: ATTR; # message aliases I'll listen to.
my %message_delay: ATTR; # Allows us to limit Messages per second
my %max_message_size: ATTR; # Maximum allowed message size before we chunk them. 
my %forum_join_grace: ATTR; # Time before we start responding to forum messages.
my %messages_sent_today: ATTR; # Tracks messages sent in 2 dimentional hash by day/hour
my %max_messages_per_hour: ATTR; # Limits the number of messages per hour.
my %safety_mode: ATTR; # Tracks if we're in safety mode.

=head1 NAME

Net::Jabber::Bot - Automated Bot creation with safeties

=head1 VERSION

Version 1.1

=cut

our $VERSION = '1.1';

=head1 SYNOPSIS

Program design:
This module is an inside out Perl Module Currently it's called Net::Jabber::Bot, but I'm thinking of also releasing Net::Jabber::SafeteyBot as a child since so many things are hard coded in the base object that probably shouldn't be.

The idea behind the module is that someone creating a bot shouldn't really have to know a whole lot about how the Jabber protocol works in order to use it. It also allows us to abstract away all the things that can get a bot maker into trouble. Essentially the object helps protect the coders from their own mistakes. 

All someone should have to know and define in the program away from the object is:
1. Config - Where to connect, how often to do things, timers, etc. 
2. A function to be called by the bot object when a new message comes in. 
3. A function to be called by the bot object every so often that let's the user do background activities (check logs, monitor web pages, etc.),

The object at present has the following enforced safeties
1. Jabber client object is not directly accessible because the bot is an inside out object, forcing the user to use the Net::Jabber::Bot's interface only
2. Limits messages per second, configurable at start up, (Max is 5 per second) by requiring a sleep timer in the message sending subroutine each time one is sent.
3. Endless loops of responding to self prevented by now allowing the bot message processing function to know about messages from self 
4. Forum join grace period to prevent bot from reacting to historical messages
5. Configurable aliases the bot will respond to 
6. Limits maximum message size, preventing messages that are too large from being sent (largest configurable message size limit is 1000). 
7. Automatic chunking of messages to split up large messages in message sending subroutine
8. ADDED YESTERDAY: Limit on messages per hour. (max configurable limit of 125) Messages will alert in the log, but not ever be sent once the message limit is reached for that hour. 

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 FUNCTIONS

=over 4

=item B<new>

my $bot = Net::Jabber::Bot->new({
                                 server => 'host.domain.com'
                                , conference_server => 'conference.host.domain.com'
                                , port => 522
                                , username => 'username'
                                , password => 'pasword'
                                , alias => 'cpan_bot'
                                , message_callback => \&new_bot_message
                                , background_activity => \&background_checks
                                , loop_sleep_time => 15
                                , process_timeout => 5
                                , forums => \@forums_to_join
                                , aliases_to_respond_to => \@responses
                                , ignore_server_messages => 1
                                , ignore_self_messages => 1
                                , out_messages_per_second => 4
                                , max_message_size => 1000
                                , max_messages_per_hour => 100
                            });


Setup the object and connect to the server. Hash values are passed to new as a ref (I think) uses Class::Std

The following initialization variables can be passed. Only marked variables are required (TODO)

=over 5

=item B<safety_mode>

    safety_mode = (1,0,'on','off')

Determines if the bot safety features are turned on and enforced. This mode is on by default. Many of the safety features are here to assure you do not crash your favorite jabber server with floods, etc. DO NOT turn it off unless you're sure you know what you're doing (not just Sledge Hammer ceratin) 

=item B<server>

Jabber server name

=item B<conference_server>

conferencee server (usually conference.$server_name)

=item B<port>

Defaults to 5222

=item B<username>

The user you authenticate with to access the server. Not full name, just the stuff to the left of the @...

=item B<password>

password to get into the server

=item B<alias>

This will be your nickname in rooms, as well as the login resource (which can't have duplicates). I couldn't come up with any reason these shouldn't be the same so hardcoded them to be the same.

=item B<forums>

an array ref to a list of strings that the bot will join upon login.

=item B<message_callback>

The subroutine the bot will call when a new message is recieved by the bot. Only called if the bot's logic decides it's something you need to know about.

=item B<background_activity>

The subroutine the bot will call when every so often (loop_sleep_time) to allow you to do background activities outside jabber stuff (check logs, web pages, etc.)

=item B<loop_sleep_time>

Frequency background activity is called.

=item B<process_timeout>

Time Process() will wait if no new activity is received from the server

=item B<ignore_server_messages>

Boolean value as to whether we should ignore messages sent to us from the jabber server (addresses can be a little cryptic and hard to process)

=item B<ignore_self_messages>

Boolean value as to whether we should ignore messages sent by us. 

BE CAREFUL if you turn this on!!! Turning this on risks potentially endless loops. If you're going to do this, please be sure safety is turned on at least initially.

=item B<aliases_to_respond_to>

An array ref listing the strings we look for at the front of the line to determine if we should react to the message and call the message_callback function. the alias addressed will be stripped out of the message before being passed to the callback function.

Strings are processed left to right so be careful of order.

example:

alias = mbot:, attention:

example1:

message: 'mbot: help'

passed to callback: 'help'

=item B<out_messages_per_second>

Limits the number of messages per second. Number must be <gt> 0

default: 5

safety: 5

=item B<max_message_size>

Specify maximimum size a message can be before it's split and sent in pieces.

default: 1,000,000

safetey: 1,000

=item B<max_messages_per_hour>

Limits the number of messages per hour before we refuse to send them

default: 125

safetey: 166

=back

=cut

# Handle initialization of objects of this class...
sub BUILD {
    my ($self, $obj_ID, $arg_ref) = @_;

    $forum_join_grace{$obj_ID} = 20;

    # Safety mode is on unless they feed us 0 or off explicitly
    $safety_mode{$obj_ID} = $arg_ref->{'safety_mode'};
    if(!defined $safety_mode{$obj_ID} 
       || $safety_mode{$obj_ID} !~ m/^\s*off\s*$/i
       || $safety_mode{$obj_ID} != 0) {
	$safety_mode{$obj_ID} = 0;
    } else {
	$safety_mode{$obj_ID} = 1;
    }
    
    $connection_hash{$obj_ID}{'server'} = $arg_ref->{'server'};
    $connection_hash{$obj_ID}{'conference_server'} = $arg_ref->{'conference_server'};

    $connection_hash{$obj_ID}{'port'} = $arg_ref->{'port'};
    $connection_hash{$obj_ID}{'port'} = 5222 if(!defined $connection_hash{$obj_ID}{'port'});

    $connection_hash{$obj_ID}{'username'} = $arg_ref->{'username'};
    $connection_hash{$obj_ID}{'password'} = $arg_ref->{'password'};

    $connection_hash{$obj_ID}{'alias'} = $arg_ref->{'alias'};
    $connection_hash{$obj_ID}{'forums'} = $arg_ref->{'forums'}; 
    
    $self_from_ident{$obj_ID} = $self;
    $message_function{$obj_ID} = $arg_ref->{'message_callback'};
    $bot_background_activity{$obj_ID} = $arg_ref->{'background_activity'};
    
    $loop_sleep_time{$obj_ID} = $arg_ref->{'loop_sleep_time'}
        or $loop_sleep_time{$obj_ID} = 5;
    
    $process_timeout{$obj_ID} = $arg_ref->{'process_timeout'}
        or $process_timeout{$obj_ID} = 5;
        
    $connection_hash{$obj_ID}{'from_full'} =
        "$connection_hash{$obj_ID}{'username'}\@$connection_hash{$obj_ID}{'server'}/$connection_hash{$obj_ID}{'alias'}";

    $ignore_messages{$obj_ID}{ignore_server_messages} = $arg_ref->{'ignore_server_messages'};
    $ignore_messages{$obj_ID}{ignore_server_messages} = 1 if(!defined $ignore_messages{$obj_ID}{ignore_server_messages});

    $ignore_messages{$obj_ID}{ignore_self_messages} = $arg_ref->{'ignore_self_messages'};
    $ignore_messages{$obj_ID}{ignore_self_messages} = 1 if(!defined $ignore_messages{$obj_ID}{ignore_self_messages});

    $aliases_to_respond_to{$obj_ID} = $arg_ref->{'aliases_to_respond_to'};
    
    my $out_messages_per_second = $arg_ref->{'out_messages_per_second'};
    $out_messages_per_second = 5 
	if(!defined $out_messages_per_second || $out_messages_per_second <= 0); # Can't be < 0 or undef

    $message_delay{$obj_ID} = 1 / $out_messages_per_second;

    # Set the maximum chunk size to fed value if it's reasonable.
    if(defined $arg_ref->{'max_message_size'} && $arg_ref->{'max_message_size'} > 100) { # Can't be < 100 (don't be silly)
	$max_message_size{$obj_ID} = $arg_ref->{'max_message_size'};
    } else {
	$max_message_size{$obj_ID} = 1,000,000; # Set it to one meg if not specified.
    }

    # Set the maximum messages per day limit to fed value if it's within reason
    if(defined $arg_ref->{'max_messages_per_hour'} && $arg_ref->{'max_messages_per_hour'} > 0) { # Must be undef and > 0
        $max_messages_per_hour{$obj_ID} = $arg_ref->{'max_messages_per_hour'};
    } else {
        $max_messages_per_hour{$obj_ID} = 1,000,000; # Set it to a really big number (Safety will catch if you're not dumb enough to disable it.)
    }


    # Initialize today's message count.
    my $yday = (localtime)[7];
    my $hour = (localtime)[2];
    $messages_sent_today{$obj_ID}{$yday}{$hour} = 0;

    # Enforce all our safety restrictions here.
    if($safety_mode{$obj_ID}) {
	# more than 5 messages per second risks server flooding.
	$safety_mode{$obj_ID} = 1/5 if($message_delay{$obj_ID} < 1/5);

	# Messages should be small to not overwhelm rooms/people/server
	$max_message_size{$obj_ID} = 1000 if($max_message_size{$obj_ID} > 1000);

	# More than 4,000 messages a day is a little excessive.
	$max_messages_per_hour{$obj_ID} = 125 if($max_message_size{$obj_ID} > 166); 

	# Shouldn't be responding to self messages to prevent loops. 
	$ignore_messages{$obj_ID}{ignore_self_messages} = 1;
    }
}

=item B<START>

Sets up the special message handling and then initializes the connection.

=cut 

sub START {
    my ($self, $obj_ID, $arg_ref) = @_;
    CreateJabberNamespaces();
    $self->InitJabber();
}

# Sets up special name space handling. 
sub CreateJabberNamespaces : PRIVATE {
    Net::Jabber::Namespaces::add_ns(  ns => "jabber:iq:version",
				      tag   => "query",
				      xpath => {
					  name       => { type=>'scalar' },
					  version  => { type=>'scalar' },
					  os      => { type=>'scalar' },
				      }
				      );
}

# Creates client object and manages connection. Called on new but also called by re-connect
sub InitJabber : PRIVATE {
    my $self = shift;
    my $obj_ID = $self->_get_obj_id() or return;
    
    DEBUG("new client object.");
    my $connection = new Net::Jabber::Client();
    $jabber_client{$obj_ID} = $connection;
    
    DEBUG("Set the call backs.");

    $connection->PresenceDB(); # Init presence DB.
    $connection->SetCallBacks('message'=>\&ProcessJabberMessage
                              ,'presence'=>\&JabberPresenceMessage
                              ,'iq'=>\&InIQ);

    DEBUG("Connect. hostname => $connection_hash{$obj_ID}{'server'} , port => $connection_hash{$obj_ID}{'port'}");
    my $status = $connection->Connect(hostname=>$connection_hash{$obj_ID}{'server'} , port=>$connection_hash{$obj_ID}{'port'});

    if(!defined $status) {
	ERROR("ERROR:  Jabber server is down or connection was not allowed: $!");
	return;
    }
        

    DEBUG("Logging in... as user $connection_hash{$obj_ID}{'username'}/$connection_hash{$obj_ID}{'alias'}");
    my @auth_result = $connection->AuthSend(username=>$connection_hash{$obj_ID}{'username'},
                                            password=>$connection_hash{$obj_ID}{'password'},
                                            resource=>$connection_hash{$obj_ID}{'alias'});

    if(!defined $auth_result[0] || $auth_result[0] ne "ok") {
	ERROR("ERROR: Authorization failed:");
	foreach my $result (@auth_result) {
	    ERROR("$result");
	}
	return;
    }

 
    $connection_session_id{$obj_ID} = $connection->{SESSION}->{id};

    DEBUG("Sending presence to tell world that we are logged in");
    $connection->PresenceSend();
    $self->Process(5);

    DEBUG("Getting Roster to tell server to send presence info");
    $connection->RosterGet();
    $self->Process(5);

    foreach my $forum (@{$connection_hash{$obj_ID}{'forums'}}) {
        $self->JoinForum($forum);
    }

    $client_start_time{$obj_ID} = time; # Track when we came online.
    return 1;
}

=item B<JoinForum> - PUBLIC

Joins a jabber forum and sleeps safety time. Also prevents the object 
from responding to messages for a grace period in efforts to get it to 
not respond to historical messages. This has failed sometimes.

NOTE: No error detection for join failure is present at the moment. (TODO)

=cut

sub JoinForum {
    my $self = shift;
    my $obj_ID = $self->_get_obj_id() or return;
    
    my $forum_name = shift;
    
    DEBUG("Joining $forum_name on $connection_hash{$obj_ID}{'conference_server'} as $connection_hash{$obj_ID}{alias}");
    $jabber_client{$obj_ID}->MUCJoin(room    => $forum_name
				     , server => $connection_hash{$obj_ID}{'conference_server'}
				     , nick   => $connection_hash{$obj_ID}{'alias'}
				     );
    
    $forum_join_time{$obj_ID}{$forum_name} = time;
    DEBUG("Sleeping $message_delay{$obj_ID} seconds");
    Time::HiRes::sleep $message_delay{$obj_ID};
}

=item B<Process> - PUBLIC

Mostly calls it's client connection's "Process" call. 
Also assures a timeout is enforced if not fed to the subroutine
You really should not have to call this very often. 
You should mostly be calling Start() and just let the Bot kernel handle all this.

=cut

sub Process { # Call connection process.
    my $self = shift;
    my $obj_ID = $self->_get_obj_id() or return;
    my $timeout_seconds = shift;
    
    #If not passed explicitly
    $timeout_seconds = $process_timeout{$obj_ID} if(!defined $timeout_seconds); 

    my $process_return = $jabber_client{$obj_ID}->Process($timeout_seconds);
    return $process_return;
}

=item B<Start> - PUBLIC

Primary subroutine save new called by the program. Does an endless loop of:
1. Process
2. If Process failed, Reconnect to server over larger and larger timeout
3. run background process fed from new, telling it who I am and how many loops we\'ve been through.
4. Enforce a sleep to prevent server floods.

=cut

sub Start {
    my $self = shift;
    my $obj_ID = $self->_get_obj_id() or return;

    my $time_between_background_routines = $loop_sleep_time{$obj_ID};
    my $process_timeout = $process_timeout{$obj_ID};
    my $background_subroutine = $bot_background_activity{$obj_ID};
    my $message_delay = $message_delay{$obj_ID};
    
    my $last_background = time - $time_between_background_routines - 1; # Call background process every so often...
    my $counter = 0; # Keep track of how many times we've looped. Not sure if we'll use this long term.

    while(1) { # Loop for ever!
	# Process and re-connect if you have to.
	my $reconnect_timeout = 1;
	while(!defined $self->Process($process_timeout)) {
	    Time::HiRes::sleep $reconnect_timeout++; # Timeout Progressiveley longer.
	      my $message = "Disconnected from $connection_hash{$obj_ID}{'server'}:$connection_hash{$obj_ID}{'port'}"
		  . " as $connection_hash{$obj_ID}{'username'}."; 
	      ERROR("$message Reconnecting...");
	      $self->ReconnectToServer();
	      next; # Don't allow background to run till you've re-connected.
	}

        # Call background function
	if(defined $background_subroutine && $last_background + $time_between_background_routines < time) {
	    &$background_subroutine($self, ++$counter);
	    $last_background = time;
	} 
        
        Time::HiRes::sleep $message_delay;
    }
}

=item B<ReconnectToServer> - PUBLIC

You should not ever need to use this. the Start() kernel usually figures this out and calls it. 

Internal process
1. Disconnects
3. Re-initializes

=cut

sub ReconnectToServer {
    my $self = shift;

    $self->Disconnect();
    $self->InitJabber();
}

=item B<Disconnect> - PUBLIC

    Disconnects from server if client object is defined. Assures the client object is deleted.

=cut


sub Disconnect {
    my $self = shift;
    my $obj_ID = $self->_get_obj_id() or return; # Not an object.


    return -1 if(!defined($jabber_client{$obj_ID})); # do not proceed, no object.

    $jabber_client{$obj_ID}->Disconnect();
    delete $jabber_client{$obj_ID};
    return 1;
}

=item B<ProcessJabberMessage> - DO NOT CALL

Handles incoming messages ***NEED VERY GOOD DOCUMENTATION HERE***** (TODO)

=cut

sub ProcessJabberMessage {
    my $session_id = shift;
    my $message = shift;

    my $self = _which_object_am_i($session_id);
    my $obj_ID = $self->_get_obj_id() or return;
    
    my $type = $message->GetType();
    my $fromJID = $message->GetFrom("jid");
    my $from_full = $message->GetFrom();
    
    my $from = $fromJID->GetUserID();
    my $resource = $fromJID->GetResource();
    my $subject = $message->GetSubject();
    my $body = $message->GetBody();

    my $reply_to = $from_full;
    $reply_to =~ s/\/.*$// if($type eq 'groupchat');

    my $message_date_text = $message->GetTimeStamp();
#    my $message_date = UnixDate($message_date_text, "%s") - 1*60*60; # Convert to EST from CST;
    
    # Ignore any messages within 20 seconds of start or join of that forum
    my $grace_period = $forum_join_grace{$obj_ID};
    my $time_now = time;
    if($client_start_time{$obj_ID} > $time_now - $grace_period
       || (defined $forum_join_time{$obj_ID}{$from} && $forum_join_time{$obj_ID}{$from} > $time_now - $grace_period)) {
	my $cond1 = "$client_start_time{$obj_ID} > $time_now - $grace_period";
	my $cond2 = "$forum_join_time{$obj_ID}{$from} > $time_now - $grace_period";
	DEBUG("Ignoring messages cause I'm in startup for forum $from\n"
	      . "$cond1\n"
	      . "$cond2");
        return; # Ignore messages the first few seconds.
    }
    
    # Ignore Group messages with no resource on them. (Server Messages?)
    if($ignore_messages{$obj_ID}{ignore_server_messages}) {
        if($from_full !~ m/^([^\@]+)\@([^\/]+)\/(.+)$/) {
	    DEBUG("Server message? ($from_full)");
            return if($from_full !~ m/^([^\@]+)\@([^\/]+)\//); 
            ERROR("Couldn't recognize from_full ($from_full). Ignoring message: $body");
            return;
        }
    }
	
	# Are these my own messages?
    if($ignore_messages{$obj_ID}{ignore_self_messages}) {
	my $bot_alias = $self->get_alias();
	DEBUG("Ignoring message from self...\n");
        return if(defined $resource && $bot_alias eq $resource); # Ignore my own messages.
    }
    
	# Determine if this message was addressed to me. (groupchat only)
    my $bot_address_form;
    if(defined $aliases_to_respond_to{$obj_ID} and $type eq 'groupchat') {
        my $request;
        foreach my $address_type (@{$aliases_to_respond_to{$obj_ID}}) {
            my $qm_address_type = quotemeta($address_type);
            next if($body !~ m/^\s*$qm_address_type\s*(\S.*)$/);
            $request = $1;
	    $bot_address_form = $address_type;
            last; # Don't need to loop any more.
        }

        return if(!defined $request); 
        $body = $request; 
    }

    if(defined $message_function{$obj_ID}) {
        my $subroutine = $message_function{$obj_ID};
        &$subroutine($self, $from_full, $body, $type, $reply_to, $bot_address_form, $message);
        return;
    } else {
        WARN("No handler for messages!");
        INFO("New Message: $type from $from ($resource). sub=$subject -- $body");
    }


}

=item B<get_alias> - PUBLIC

Returns the alias name we are connected as or undef if we are not an object

=cut

sub get_alias {
    my $self = shift;
    my $obj_ID = $self->_get_obj_id() or return;
        
    return $connection_hash{$obj_ID}{'alias'};
}

# Supposed to respond to version requests. *** NOT WORKING YET ****
sub Version : PRIVATE {
    my $self = shift;
    my $obj_ID = $self->_get_obj_id() or return;

    my $iq = new Net::XMPP::IQ();
    $iq->SetIQ(to=> 'todd.e.rinaldo@mx-dev.jpmorgan.com/Shiva'
	       , from=> 'murex.bot@mx-dev.jpmorgan.com/Murex-Bot'
	       , id=>   'jcl_122'
	       , type=> 'get'
	       );
    my $iqType = $iq->NewChild( 'jabber:iq:version' );
    DEBUG("Sending IQ Message:" . $iq->GetXML());
    $jabber_client{$obj_ID}->Send($iq)
}

=item B<InIQ> - DO NOT CALL

Called when the client receives new messages during Process of this type. 

=cut

sub InIQ {
    my $session_id = shift;
    my $iq = shift;

    my $self = _which_object_am_i($session_id);
    my $obj_ID = $self->_get_obj_id() or return;

    DEBUG("IQ Message:" . $iq->GetXML());
#    my $from = $iq->GetFrom();DEBUG("From=$from");
#    my $type = $iq->GetType();DEBUG("Type=$type");
    my $query = $iq->GetQuery();DEBUG("query=$query");
    my $xmlns = $query->GetXMLNS();DEBUG("xmlns=$xmlns");
    my $iqReply;

    if($xmlns eq "jabber:iq:version") {
	return;
	$iqReply = new Net::XMPP::IQ();
	my $iqType = $iqReply->NewChild( 'jabber:iq:version' );
	$iqType->Setname("test");
#	$iqReply->Set("name", "Perl");
	DEBUG("version");
    } else {
	return;
    }

    DEBUG("Reply: ", $iqReply->GetXML());
    $jabber_client{$obj_ID}->Send($iqReply);

#    $from = "" if(!defined $from);
#    $type = "" if(!defined $type);
#    $query = "" if(!defined $query);
#    $xmlns = "" if(!defined $xmlns);

#    INFO("IQ from $from ($type). XMLNS: $xmlns");
}

=item B<JabberPresenceMessage> - DO NOT CALL

Called when the client receives new presence messages during Process. 
Mostly we are just pushing the data down into the client DB for later processing.

=cut 

sub JabberPresenceMessage {
    my $session_id = shift;
    my $presence = shift;
    
    my $self   = _which_object_am_i($session_id);
    my $obj_ID = $self->_get_obj_id() or return;
    
    my $type = $presence->GetType();
    if($type eq 'subscribe') { # Always allow people to subscribe to us. Why wouldn't we?
	my $from = $presence->GetFrom();
	$jabber_client{$obj_ID}->Subscription(type=>"subscribed",
					      to=>$from);
	INFO("Processed subscription request from $from");
	return;
    } elsif($type eq 'unsubscribe') { # Always allow people to subscribe to us. Why wouldn't we?
        my $from = $presence->GetFrom();
        $jabber_client{$obj_ID}->Subscription(type=>"unsubscribed",
                                              to=>$from);
        INFO("Processed unsubscribe request from $from");
        return;
    }

    $jabber_client{$obj_ID}->PresenceDBParse($presence); # Since we're always an object just throw it into the db.

    my $from = $presence->GetFrom();
    $from = "." if(!defined $from);

    my $status = $presence->GetStatus();
    $status = "." if(!defined $status);

    INFO("Presence From $from t=$type s=$status");
    DEBUG("Presence XML: " . $presence->GetXML());
}

=item B<respond_to_self_messages> - PUBLIC

    $bot->respond_to_self_messages($value = 1);


Tells the bot to start reacting to it\'s own messages if non-zero is passed. Default is 1.

=cut


sub respond_to_self_messages {
    my $self = shift;
    my $obj_ID = $self->_get_obj_id() or return "Not an object\n"; #Failure

    my $setting = shift;
    $setting = 1 if(!defined $setting);

    $ignore_messages{$obj_ID}{ignore_self_messages} = !$setting;
    return $setting;
}

=item B<get_messages_this_hour> - PUBLIC

    $bot->get_messages_this_hour();

replys with number of messages sent so far this hour.

=cut


sub get_messages_this_hour {
    my $self = shift;
    my $obj_ID = $self->_get_obj_id() or return; #Failure

    my $yday = (localtime)[7];
    my $hour = (localtime)[2];
    my $messages_this_hour = $messages_sent_today{$obj_ID}{$yday}{$hour};
    return $messages_this_hour;
}

=item B<get_safety_mode> - PUBLIC

Validates that we are in safety mode. Returns a bool as long as we are an object, otherwise returns undef

=cut

sub get_safety_mode {
    my $self = shift;
    my $obj_ID = $self->_get_obj_id() or return;

    # Must be in safety mode and all thresholds met. 
    my $mode = !!($safety_mode{$obj_ID}
		  && $message_delay{$obj_ID} >= 1/5
		  && $max_message_size{$obj_ID} <= 1000
		  && $max_message_size{$obj_ID} <= 166
		  && $ignore_messages{$obj_ID}{ignore_self_messages}
		  );
    return $mode;
}

=item B<SendGroupMessage> - PUBLIC

    $bot->SendGroupMessage($name, $message);

Tells the bot to send a message to the recipient room name

=cut

sub SendGroupMessage {
    my $self = shift;
    my $recipient = shift;
    my $message = shift;

    my $obj_ID = $self->_get_obj_id() or return;
    $recipient .= '@' . $connection_hash{$obj_ID}{'conference_server'} if($recipient !~ m{\@});

    return $self->SendJabberMessage($recipient, $message, 'groupchat');
}

=item B<SendPersonalMessage> - PUBLIC

    $bot->SendPersonalMessage($recipient, $message);

How to send an individual message to someone.

$recipient must read as user@server/Resource or it will not send.

=cut

sub SendPersonalMessage {
    my $self = shift;
    my $recipient = shift;
    my $message = shift;

    return $self->SendJabberMessage($recipient, $message, 'chat');
}

# $bot->SendJabberMessage($recipient, $message, $message_type, $subject);
# The master subroutine to send a message. Called either by the user, SendPersonalMessage, or SendGroupMessage.
# Assures message size does not exceed a limit and chops it into pieces if need be.

sub SendJabberMessage : PRIVATE {
    my $self = shift;
    my $obj_ID = $self->_get_obj_id() or return;
   
    my $recipient = shift;
    my $message = shift;
    my $message_type = shift;
    my $subject = shift;
    
    my $max_size = $max_message_size{$obj_ID};

    # Split the message into no more than max_message_size so that we don't piss off jabber.
    # Split on new line. Space if you have to or just chop at max size.
    my @message_chunks = ( $message =~ /.{1,$max_size}$|.{1,$max_size}\n|.{1,$max_size}\s|.{1,$max_size}/gs ); 


    DEBUG("Max message = $max_size. Splitting...") if($#message_chunks > 0);
    my $return_value;
    foreach my $message_chunk (@message_chunks) {
	my $msg_return = $self->_SendIndividualMessage($recipient, $message_chunk, $message_type, $subject);
	if(defined $msg_return) {
	    $return_value .= $msg_return;
	}
    }
    return $return_value;
}

# $self->_SendIndividualMessage($recipient, $message_chunk, $message_type, $subject);
# Private subroutine only called directly by SetForumSubject and SendJabberMessage.
# There are a bunch of fancy things this does, but the important things are:
# 1. sleep a minimum of .2 seconds every message
# 2. Make sure we have not sent too many messages this hour and block sends if they are attempted over a certain limit (max limit is 125)
# 3. Strip out special characters that will get us booted from the server.

sub _SendIndividualMessage : PRIVATE {
    my $self = shift;
    my $obj_ID = $self->_get_obj_id() or return "Not an object\n"; #Failure
    
    my $recipient = shift;
    my $message_chunk = shift;
    my $message_type = shift;
    my $subject = shift;

    if(!defined $message_type) {
        ERROR("Undefined \$message_type");
        return "No message type!\n";
    }

    if(!defined $recipient) {
	ERROR('$recipient not defined!');
	return "No recipient!\n";
    }
    
    my $yday = (localtime)[7];
    my $hour = (localtime)[2];
    my $messages_this_hour = ++$messages_sent_today{$obj_ID}{$yday}{$hour};
    
    if($messages_this_hour > $max_messages_per_hour{$obj_ID}) {
	$subject = "" if(!defined $subject); # Keep warning messages quiet.
	$message_chunk = "" if(!defined $message_chunk); # Keep warning messages quiet.

	ERROR("Can't Send message because we've already tried to send $messages_this_hour of $max_messages_per_hour{$obj_ID} messages this hour.\n"
	      . "To: $recipient\n"
	      . "Subject: $subject\n"
	      . "Type: $message_type\n"
	      . "Message sent:\n"
	      . "$message_chunk"
	      );
	
	# Send 1 panic message out to jabber if this is our last message before quieting down.
	return "Too many messages ($messages_this_hour)\n";
    }

    $message_chunk =~ s/[^ -~\r\n]/./g; #Strip out anything that's not a printable character

    my $message_length = length($message_chunk);
    DEBUG("Sending message $yday-$hour-$messages_this_hour $message_length bytes to $recipient");
    $jabber_client{$obj_ID}->MessageSend(to => $recipient
					 , body => $message_chunk
					 , type => $message_type
#                                        , from => $connection_hash{$obj_ID}{'from_full'}
					 , subject => $subject
					 );

    DEBUG("Sleeping $message_delay{$obj_ID} after sending message.");
    Time::HiRes::sleep $message_delay{$obj_ID}; #Throttle messages.

    if($messages_this_hour == $max_messages_per_hour{$obj_ID}) { 
	$jabber_client{$obj_ID}->MessageSend(to => $recipient
					     , body => "Cannot send more messages this hour. "
					     . "$messages_this_hour of $max_messages_per_hour{$obj_ID} already sent."
					     , type => $message_type
					     );
    }
    return; # Means we succeeded!
}

=item B<SetForumSubject> - PUBLIC

    $bot->SetForumSubject($recipient, $subject);

Sets the subject of a forum

=cut

sub SetForumSubject {
    my $self = shift;
    my $obj_ID = $self->_get_obj_id() or return "Not an object\n"; #Failure

    my $recipient = shift;
    my $subject = shift;

    if(length $subject > $max_message_size{$obj_ID}) {
	my $subject_len = length($subject);
	ERROR("Someone tried to send a subject message $subject_len bytes long!");
	my $subject = substr($subject, 0, $max_message_size{$obj_ID});
	DEBUG("Truncated subject: $subject");
	return "Subject is too long!";
    }
    $self->_SendIndividualMessage($recipient, "Setting subject to $subject", 'groupchat', $subject);

    return;
}

# $bot->_get_obj_id();
# Retrieves the ident of the local object and does a default bail if the caller had not initialized the object. does not die by design.

sub _get_obj_id : PRIVATE {
    my $self = shift;
    my $obj_ID = ident($self);
    
    return $obj_ID if(defined $obj_ID);
    
    my ($package, $filename, $line) = caller(1);
    my ($package_caller, $filename_caller, $line_caller) = caller(2);

    $line_caller = 'unknown' if(!defined $line_caller);
    $filename_caller = 'unknown' if(!defined $filename_caller);
    $package = 'unknown' if(!defined $package);

    ERROR("$package called at line $line_caller in $filename_caller without a valid object!!");
    return;
}

# Allows the message processors to figure out what object ($self) they are based
# on the session_id, which is all that the connection feeds to the routines when
# they get a new message.

sub _which_object_am_i : PRIVATE{
    my $session_id = shift;
    
    foreach my $obj_ID (keys %connection_session_id) {
        return $self_from_ident{$obj_ID} if($connection_session_id{$obj_ID} eq $session_id);
    }

    my ($package, $filename, $line) = caller(1);
    ERROR("Can't find object that owns $session_id in $package!!");
    return;
}

=back

=head1 AUTHOR

Todd E Rinaldo, C<< <todd.e.rinaldo at jpmorgan.com> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-net-jabber-bot at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Net-Jabber-Bot>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Net::Jabber::Bot

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Net-Jabber-Bot>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Net-Jabber-Bot>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Net-Jabber-Bot>

=item * Search CPAN

L<http://search.cpan.org/dist/Net-Jabber-Bot>

=back

=head1 ACKNOWLEDGEMENTS

=head1 COPYRIGHT & LICENSE

Copyright 2007 Todd E Rinaldo, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of Net::Jabber::Bot

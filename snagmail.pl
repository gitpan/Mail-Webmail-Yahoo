#!/usr/bin/perl -w

#  Simon Drabble	03/22/02
#  sdrabble@cpan.org
#  $Id: snagmail.pl,v 1.13 2003/01/18 03:53:07 simon Exp $
#


use strict;

use Mail::Webmail::Yahoo;

my $name = $ARGV[0] or &usage, die;
my $pass = $ARGV[1] or &usage, die;


## Hide the password.. doesn't work on some systems. Also may not be able to
## assign to $0, so copy it first.
my $prog = $0;
$prog =~ s/\s.*//g;
$0 = $prog;


my $yahoo = new Mail::Webmail::Yahoo(
		username => $name,
		password => $pass,
		cookie_file => './cookies',
		);

$| = 1;


# Set this to a positive number for more debugging.
$yahoo->trace(1);

my @fetchnums;
my $msg_list;
if (lc $ARGV[2] eq 'all') {
	$msg_list = 'all';
} elsif ($ARGV[2]) {
	eval { @fetchnums = (eval $ARGV[2]) };
	$msg_list = \@fetchnums;
}

my $flags = 0;
my $move_to = '';

# If you wish to delete messages on server after downloading, uncomment this:
#$flags |= DELETE_ON_READ;

# If you wish to move messages after downloading, uncomment the next 2 lines:
# Note that MOVE_ON_READ has precedence over DELETE_ON_READ.
#$flags |= MOVE_ON_READ;
#$move_to = "INSERT YOUR FOLDER NAME HERE"; 


if ($flags & MOVE_ON_READ && $flags & DELETE_ON_READ) {
	$flags ^= DELETE_ON_READ;
}


my @messages = $yahoo->get_mail_messages('Inbox', $msg_list, $flags, $move_to);
print "Message Headers in Inbox: ", 0+@messages, "\n";
print "Messages will be delivered to ./${name}_Inbox.\n";
if ($flags & DELETE_ON_READ && !($flags & MOVE_ON_READ)) {
	print "Messages will be deleted from server after download.\n";
}
if ($move_to) {
	if ($flags & MOVE_ON_READ) {
		print "Messages will be moved to $move_to after download.\n";
	}
}


open INBOX, ">${name}_Inbox";
for (@messages) { print INBOX $_->as_mbox_string }
close INBOX;
print "\n";




sub usage
{
	print qq{
$0 <username> <password>  [<list of messages to retrieve>]
};	
}




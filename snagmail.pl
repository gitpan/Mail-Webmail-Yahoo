#!/usr/bin/perl -w

#  Simon Drabble	03/22/02
#  sdrabble@cpan.org
#  $Id: snagmail.pl,v 1.6 2002/10/24 21:39:23 simon Exp $
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

my @messages = $yahoo->get_mail_messages('Inbox', $msg_list);
print "Message Headers in Inbox: ", 0+@messages, "\n";
print "Messages will be delivered to ./${name}_Inbox.\n";
open INBOX, ">${name}_Inbox";
for (@messages) { print INBOX $_->as_mbox_string }
close INBOX;
print "\n";




sub usage
{
	print qq{
$0 <yahoo username> <yahoo password>  [<number of messages to download>]
};	
}




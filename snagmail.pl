#!/usr/bin/perl -w

#  Simon Drabble	03/22/02
#  sdrabble@cpan.org
#  $Id: snagmail.pl,v 1.2 2002/07/27 15:00:09 simon Exp $
#


use strict;

use Mail::Webmail::Yahoo;

my $name = $ARGV[0] or &usage, die;
my $pass = $ARGV[1] or &usage, die;

my $prog = $0;

## Hide the password.
$prog =~ s/\s.*//g;
$0 = $prog;

my $yahoo = new Mail::Webmail::Yahoo(
		username => $name,
		password => $pass,
		cookie_file => './cookies',
		);

$| = 1;


$yahoo->trace(6);

my @fetchnums;
if ($ARGV[2]) {
	eval { @fetchnums = (eval $ARGV[2]) };
}

my @messages = $yahoo->get_mail_messages('Inbox', \@fetchnums);
print "Message Headers in Inbox: ", 0+@messages, "\n";
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

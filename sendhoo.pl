#!/usr/bin/perl -w

#  Simon Drabble	03/22/02
#  sdrabble@cpan.org
#  $Id: sendhoo.pl,v 1.3 2002/10/23 22:05:41 simon Exp $
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


$yahoo->trace(1);

my $to   = $ARGV[2] or &usage, die; 
my $subj = $ARGV[3] or &usage, die; 
my $body = $ARGV[4] or &usage, die; 

$yahoo->send(
		$to,                       # to
		$subj,                     # subject
		$body,                     # body
		'',                        # cc
		'',                        # bcc
		SAVE_COPY_TO_SENT_FOLDER,  # flags
		);


sub usage
{
	print qq{
$0 <yahoo username> <yahoo password> <to-list> <subject> <body>
  to-list is a comma-separated lists of addresses.
};	
}

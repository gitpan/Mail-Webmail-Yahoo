#!/usr/bin/perl -w

#  Simon Drabble	03/22/02
#  sdrabble@cpan.org
#  $Id: sendhoo.pl,v 1.2 2002/08/10 03:07:16 simon Exp $
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


$yahoo->trace(10);

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

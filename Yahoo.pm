#  (C)  Simon Drabble 2002
#  sdrabble@cpan.org   03/22/02

#  $Id: Yahoo.pm,v 1.19 2002/04/24 17:18:32 simon Exp $
#

package Mail::Webmail::Yahoo;

require 5.6.0;

use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);

our $VERSION = 0.1;

# This is an object-based package. We export nothing.
our @EXPORT_OK = ();
our @EXPORT = ();


use Carp qw(carp);


use LWP::UserAgent;
# Turn on for mondo debugging oh yeah.
#use LWP::Debug qw(+);
use HTTP::Request;
use HTTP::Headers;
use HTTP::Cookies;
use HTML::LinkExtor;
use HTML::Entities;
use Mail::Internet;
use MIME::Base64;
use HTML::FormParser;
use HTML::TableExtractor;
use HTML::TableContentParser;
use CGI qw(escape unescape);


use Class::MethodMaker
	get_set => [qw(trace cache_messages cache_headers)];


# These next bits should ideally go in a config file or something. Or be
# passable on the command line, or overrideable in the calling app. They will
# (hopefully) never change, but if they do...
# Would prefer to 'use constant...' but that doesn't work well in regexps.
our $SERVER               = 'http://mail.yahoo.com';	
our $LOGIN_SERVER         = 'http://mail.yahoo.com';	

our $FOLDER_APP_NAME      = 'Folders';
our $SHOW_FOLDER_APP_NAME = 'ShowFolder';
our $SHOW_MSG_APP_NAME    = 'ShowLetter';
our $SHOW_TOC             = 'toc=[^\&]*';

our $FULL_HEADER_FLAG     = 'Nhead=f&head=';
our $EMPTY_FULL_HEADER_FLAG = 'head=[^\&]*&?';

our $LOGIN_FIELD          = 'login';
our $PASSWORD_FIELD       = 'passwd';
our $SAVE_USER_INFO_FIELD = '.persistent';

our $DATE_MOLESTERED_STRING = 'Date header was inserted';
our $LOOKS_LIKE_A_HEADER = q{\w+:};


our @mail_header_names = qw(
		To From Reply-To Subject Date X- Received Content- 
);



# ick.
our $DOWNLOAD_FILE_LINK = q{\s*<a href="(/ym/ShowLetter/[^"]+)">\s*<b><font[^>]*>\s*Download File\s*</b>\s*</a>};



our $NEXT_MESSAGES_LINK = q{
showing \d+-\d+ of \d+
\| <a href="(/ym/ShowFolder[^"]+)">Next</a>
};


our $MESSAGE_START_STRING = qq{
<select name="destBox">
<option value="">- Choose Folder -
.*(?!</select>)
</select>
<input type=submit name=MOV value="Move">

</font></td>

<td align=right nowrap><font[^>]*>
<input type=submit name=UNR value="Mark as Unread">
</font></td>
</tr>
};


our $MESSAGE_END_STRING = qq{
<table cellspacing=0 cellpadding=0 width="100%">
<tr>
<td colspan=3>
<hr size=1 noshade>
</td>
</tr>
<tr>
<td nowrap valign=top><font face=times size=-1>Click a <[^\>]+> to send an instant message to an online friend</td>
<td>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td>
};



sub new
{
	my $class = shift;

	my %args = @_;
	
	my $self = bless {
		_server    => $args{server}   || $SERVER,
		_username  => $args{username} || Carp::carp('No username defined'),
		_password  => $args{password} || Carp::carp('No password defined'),
		_login_server => $args{login_server}|| $args{server} || $LOGIN_SERVER,
		_cookie_file => $args{cookie_file},
		_logged_in => 0,
		_connected => 0,
		_ua        => new LWP::UserAgent,
		_retrieve  => $args{retrieve} || 'all',
	}, $class;


	if (!$self->{_ua}->is_protocol_supported('https')) {
		die "https not supported by LWP. This application will not work.\n";
	}

	$self->{_ua}->env_proxy;

	my $cookie_jar = new HTTP::Cookies::Netscape(
			File => $self->{_cookie_file},
			AutoSave => 1);

	$cookie_jar->load;

	$self->{_cookie_jar} = $cookie_jar;

	$self->{_ua}->cookie_jar($cookie_jar);

	$self->cache_messages(1);
	$self->cache_headers(1);
	
	return $self;
}


sub connect
{
	my ($self) = @_;
	return 0 if $self->{_connected};

# FIXME: really connect if necessary.
	$self->debug(" connected.") if $self->trace;
	$self->{_connected} = 1;
}


sub login
{
	my ($self) = @_;
	return 0 if $self->{_logged_in};

	$self->connect unless $self->{_connected};

	my $uri = $self->{_login_server};
	$self->debug(" requesting login page '$uri'.") if $self->trace > 3;
	my $info = $self->_get_a_page($uri, 'GET');
	my $welcome_page = $info->content;

	die "Problem getting login page" unless $welcome_page;

	my $p = new HTML::FormParser;

	my @login_params;

	$self->debug(" parsing login page.") if $self->trace > 3;

# Parse the returned 'welcome' page looking for a suspicious link to login
# with. This is kindly provided by (as of 2002-04-06 at least) the only form
# in the page. So hurrah.
# Note we don't store the login info in a cookie since it kinda makes no sense
# -- the only reason for doing so is to remove the need to enter a username in
# the login page; we provide this username in the object parameters.
# It might speed things up a little, but until Yahoo stops retiring sessions
# every eight hours or so, I'm not gonna bother re-using cookies.
	my $pobj = $p->parse($welcome_page, 
				form => sub {
					my ($attr, $origtext) = @_;
					$self->{STORED_URIS}->{login_page} = $attr; 
				},
				input => sub {
					my ($attr, $origtext) = @_;
					if ($attr->{name} eq $LOGIN_FIELD) {
						$attr->{value} = $self->{_username};
					} elsif ($attr->{name} eq $PASSWORD_FIELD) {
						$attr->{value} = $self->{_password};
					} elsif ($attr->{name} eq $SAVE_USER_INFO_FIELD) {
						$attr->{value} = '';
						$attr->{name} = '';
					}
					push @login_params, $attr;
				}
			);


	my @params;
	for (@login_params) {
		next unless $_->{name};
		push @params, "$_->{name}=$_->{value}";
	}


# This bit makes the actual request to login, having stuffed the @params array
# with the fields gleaned from the login page (plus our username and password
# of course). Note that there is some feature in LWP that doesn't like
# redirects from https.
	$uri = $self->{STORED_URIS}->{login_page}->{action};
	$uri =~ s/https/http/g;
	my $meth = $self->{STORED_URIS}->{login_page}->{method};
	for (@params) { warn "$_\n" }

	$info = $self->_get_a_page($uri, $meth, \@params);
	$welcome_page = $info->content;

	die "Couldn't log in" unless $welcome_page;

	$self->debug(" logged in.") if $self->trace;
	$self->{_logged_in} = 1;
}


sub get_mail_headers
{
	warn "get_mail_headers is deprecated -- use get_mail_messages instead.\n";
	shift->get_mail_messages(@_);
}




sub get_mail_messages
{
	my ($self, $mbox, $msg_list) = @_;


	$self->login unless $self->{_logged_in};
	$self->get_folder_list;
	my @msgs = $self->get_folder_index($mbox);

	my @messages;

	my @message_nums;
	if ($msg_list) {
		@message_nums = @{$msg_list};
		$self->debug("Fetching messages numbered @message_nums");
	}

	my $mcount = 0;
	for (@msgs) {
		++$mcount;
		next unless !@message_nums || grep { $_ == $mcount } @message_nums;

		my $uri = $_->{uri};
		$uri =~ s/$EMPTY_FULL_HEADER_FLAG//g;
		$uri .= "&" . $FULL_HEADER_FLAG;
		$uri =~ s/inc=\d+\&?//g;
		my $info = $self->_get_a_page($uri);
		my $page = $info->content;
		
		if ($page) {

			my @hdrs;

			my $p = new HTML::TableContentParser;
			my $stored_tables = $p->parse($page);

			my $from_date = '';

# Remove as much crap as possible from the page before parsing it..
			open SMIT, ">tmp/full_$mcount";
			print SMIT $page;
			close SMIT;
			$page =~ s{.+$MESSAGE_START_STRING(.+)$MESSAGE_END_STRING.+}{$1}sig;

			for my $t (@$stored_tables) {
				next unless $t->{rows};

				for my $r (@{$t->{rows}}) {
					next unless $r->{cells};

					for my $c (0..@{$r->{cells}}-1) {

# We're only interested in data that contains a message header, and the field
# associated with it -- but there may be a bunch of other crap stuck in by
# yahoo that 'looks like' a message header. So we validate against a known
# list of message headers. The first check is faster than examining every item
# of data through the grep.


						next unless my $field = $r->{cells}->[$c]->{data};
						if ($field =~ /$LOOKS_LIKE_A_HEADER/ &&
								grep { $field =~ /^$_.*:/i } @mail_header_names) {

							my $data = $r->{cells}->[$c+1]->{data};

							chomp $data;

# 'From' header has 'block address crap in it..
							if ($field =~ /From/) {
								$data =~ s/\&nbsp;\|.*//g;

# Also add a 'From' line so pine et al recognise it as a message.
								my $from = HTML::Entities::decode($data); 
								$from =~ s/".*"//g;
								$from =~ s/<|>//g;

								push @hdrs, "From $from";

							} elsif ($field =~ /Date/) {
# Sometimes the date field gets molestered..
								if ($data =~ /$DATE_MOLESTERED_STRING/) {
									$data = ' ' . scalar localtime time;
								}
#								($from_date = $data) =~ s/,//g;
								$from_date =  ' ' . scalar localtime time;
							}

							push @hdrs, "$field " . HTML::Entities::decode($data);
							++$c;

						}
					}
				}
			}
				
# Sort the headers so 'From' comes first..
			my $hdr = [sort { $a =~ /^From\s+/ ? -1 : 1 } @hdrs];
# ..and add the date to the 'From' header, so it looks like mail.
			$hdr->[0] .= $from_date;
			my $mhdr = new Mail::Internet($hdr);

			push @messages, $mhdr;

# So much for the header, now for the body.. This gets a little trickier since
# there is nothing simple to trigger off.
# It /appears/ that yahoo very kindly sticks three blank lines before 
# each message body... so let's try that to get the start of the message. The
# end will be a little harder...

			my @body = $page =~ /\n\n\n\n(.*)/is;
			open FOO, ">tmp/page_$mcount";
			print FOO $page;
			close FOO;
			$mhdr->body(@body, "\n");

			(my $prog = $0) =~ s/\s+\d+\s+messages//g;
			$prog .= ' ' . (0+@messages) . ' messages';
			$0 = $prog;

# Check for downloadable attachments, mime-encode, and stuff into the message
# using some magic to set content types etc.
			while ($page =~ s{$DOWNLOAD_FILE_LINK}{}si) {
				my $download_link = $1;
				my $url = new URI::URL($_->{uri});
				$download_link .= $FULL_HEADER_FLAG;
				my $link = $url->scheme . '://' . $url->host . $download_link;
				my $att = $self->download_attachment($link, $mhdr);
			}

			print 0+@messages, " messages\n" if (!(@messages % 20));

			if ($self->{_retrieve} =~ /^(\d+)$/  && @messages >= $1) {
				return @messages
			}


		} else {

			warn "Couldn't retrieve message id $_->{id}\n";

		}
	}

	return @messages;
}



sub download_attachment
{
	my ($self, $download_link, $snagmsg) = @_;

	my ($filename) = $download_link =~ /filename=([^\&]*)/;
	print "Downloadable: $filename\n";
	my $info = $self->_get_a_page($download_link);

	if ($snagmsg) {
		$self->add_attachment_to_message($snagmsg, $info, $filename);
	}

	return $info;
}




sub add_attachment_to_message
{
	my ($self, $msg, $att, $filename) = @_;

	my $filedata = $att->content;

	my $ct = $msg->get('Content-Type');

	if ($ct !~ /multipart\/mixed/) {
		$msg->replace('Content-Type', $self->make_multipart_boundary($msg));
		$ct = $msg->get('Content-Type');
	} 
	my ($bndry) = $ct =~ /boundary="([^"]+)"/;
	$msg->replace('MIME-Version', '1.0');

##		--0-1260933182-1019570195=:33950
##			Content-Type: text/plain; charset=us-ascii
##			Content-Disposition: inline

	my @body = @{$msg->body};
	unshift @body, "--$bndry\n",  
		"Content-Type: text/html;  charset=us-ascii\n",
		"Content-Disposition: inline;\n\n";

	my $encoded_data = MIME::Base64::encode_base64($filedata);

	push @body, "--$bndry\n",
		"Content-Type: ", join('; ', $att->content_type), "\n",
		"Content-Transfer-Encoding: base64\n",
		"Content-Disposition: attachment; filename=$filename\n\n",
 		$encoded_data;
	$msg->body(@body);
	
}




sub get_folder_index
{
	my ($self, $mbox, $callback) = @_;

	$mbox ||= 'Inbox';
	$self->login unless $self->{_logged_in};

	if (!$self->{STORED_URIS}->{folder_list}->{$mbox}) {
		die "No such folder '$mbox' found in list.\n";
	}

	my $uri = $self->{STORED_URIS}->{folder_list}->{$mbox};
	my $info = $self->_get_a_page($uri);
	my $index = $info->content;

	$self->{STORED_PAGES}->{message_index}->{$mbox}->[0] = $index;

	my @msgs;

	if ($index) { push @msgs, $self->_get_message_links($index) }

	my $has_more = '';
	do {
		my ($next_page) = $index =~ /$NEXT_MESSAGES_LINK/i;
		$has_more = $next_page ? 1 : 0;
		if ($has_more) {
			my $url = new URI::URL($uri);
			my $link = $url->scheme . '://' . $url->host . $next_page;
			$index = $self->_get_a_page($link)->content;
			if ($index) { push @msgs,  $self->_get_message_links($index) }
		}

	} while ($has_more);

	return @msgs;
}


sub _get_message_links
{
	my ($self, $page) = @_;
	my @msgs;
	my $p = new HTML::LinkExtor(
			sub
			{
				my ($tag, $type, $uri) = @_;
				if ($type eq 'href' &&
						$uri =~ /$SHOW_MSG_APP_NAME\?.*MsgId=([^\&]*)/i &&
						$uri !~ /$SHOW_TOC/i) {
					$self->debug(" get_message_list: $uri") if $self->trace;
					$self->{STORED_URIS}->{messages}->{$1} = $uri;
# Use a separate array here rather than simply returning the keys of the
# STORED_URIS->message hash since we're only interested in one folder.
					push @msgs, {
						id => $1,
						uri => $uri,
						};
				}
			},
			$self->{_folder_uri} || $self->{_server});

	$p->parse($page);

	return @msgs;
}


sub get_folder_list
{
	my ($self) = @_;
	$self->login unless $self->{_logged_in};

	my $index = $self->{STORED_PAGES}->{initial};
	if (!$index) {
		my $info = $self->_get_a_page($self->{_server});
		my $server = $info->request->uri;
		$index = $info->content;
		$self->{_folder_uri} = $server;
	}


	if (!$self->{STORED_URIS}->{front_page}) {
		my $p = new HTML::LinkExtor(
				sub
				{
					my ($tag, $type, $uri) = @_;
					if ($type eq 'href' && $uri =~ /$FOLDER_APP_NAME\?/) {
						$self->{STORED_URIS}->{front_page} = $uri;
					}
				},
				$self->{_folder_uri} || $self->{_server});

		$p->parse($index);
	}

	if ($self->{STORED_URIS}->{front_page}) {
		my $indp = $self->{STORED_PAGES}->{index_page} ||
			$self->_get_a_page($self->{STORED_URIS}->{front_page})->content;

		my $p = new HTML::LinkExtor(
				sub
				{
					my ($tag, $type, $uri) = @_;
					if ($type eq 'href' &&
							$uri =~ /$SHOW_FOLDER_APP_NAME\?.*box=([^\&]*)/) {
						$self->debug(" get_folder_list: $uri") if $self->trace;
						$self->{STORED_URIS}->{folder_list}->{$1} = $uri;
					}
				},
				$self->{_folder_uri} || $self->{_server});

		$p->parse($indp);
	}

	return keys %{$self->{STORED_URIS}->{folder_list}};
}



# FIXME: allow $params to be a hashref perhaps
sub _get_a_page
{
	my ($self, $uri, $method, $params) = @_;

	return undef unless $uri;

	$method ||= 'GET';
	$method =~ tr/a-z/A-Z/;

#	$uri =~ s/https/http/g;

	my $req = new HTTP::Request($method, $uri);

  my $post_content = '';
	if (ref($params) eq 'ARRAY') {
		my @vars;
		for (@$params) {
			my ($name, $value) = $_ =~ /([^=]*)=(.*)/;
			push @vars, "$name=" . CGI::escape($value);
		}
		my $char = $method eq 'GET' ? '&' : "\n";
		$char = '&';
		$post_content = join $char, @vars;
	}



	if ($post_content) {
		if ($method =~ /POST/) {
			$req->content($post_content);
			$req->content_type('application/x-www-form-urlencoded');
			$req->content_length(length $post_content);
		} elsif ($method =~ /GET/) {
			$uri .= "?$post_content";
			$uri =~ s/\?([^\?]*)\?/?$1&/g;
		}

	}

	$self->debug(" requesting uri '$uri' via $method.") if $self->trace;
	$self->debug(" parameters: $post_content") if $post_content && $self->trace;

	$self->debug(" Request: === \n", $req->as_string, "===\n") if $self->trace > 12;

	$req->header(pragma => 'no-cache');

	$req->header(Accept => 'text/html, text/plain, application/x-director, application/x-shockwave-flash, image/x-quicktime, video/quicktime, image/jpeg, image/*, application/x-gunzip, application/x-gzip, application/x-bunzip2, application/x-tar-gz, audio/*, video/*, text/sgml, video/mpeg, image/jpeg, image/tiff, image/x-rgb, image/png, image/x-xbitmap, image/x-xbm, image/gif, application/postscript, */*;q=0.01');


#	$req->header(Accept_Encoding => 'gzip, compress');
	$req->header(Accept_Language => '*');
	$req->header(Cache_Control => 'no-cache');
	$req->header(Referer => 'file://none.html');
	
#	$self->{_cookie_jar}->add_cookie_header($req);
	my $resp = $self->{_ua}->request($req);

	$self->{_cookie_jar}->extract_cookies($resp);
	$self->{_cookie_jar}->save;
	
	$self->debug(" Response = \n", $resp->as_string, "\n =\n") if $self->trace > 9;
	$self->debug(" returned code ", $resp->code, ".") if $self->trace;
	if ($self->trace > 1) {
		$self->debug(" request uri ", $resp->request->url);
	}
	if ($self->trace > 8) {
		$self->debug(" request contents ", $resp->content);
	}

# FIXME: Not sure about this guy. Seems like redirects are always gonna be
# GETs even if the original request was a POST. Little bit of hokum from Yahoo
# with their multiple-302 chain.
	if ($resp->code == 302) {
		$uri = $resp->header('Location');
		$self->debug(" 302 (Moved Temporarily) to $uri encountered.")
			if $self->trace > 3;
		return $self->_get_a_page($uri, 'GET', $params);
	}
	
	return $resp;
}



sub debug
{
	my $self = shift;
	warn __PACKAGE__, ": @_\n";
}


1;

__END__

=head1 NAME

Mail::Webmail::Yahoo - Enables bulk download of yahoo.com -based webmail.

=head1 SYNOPSIS

  use Mail::Webmail::Yahoo;
  $yahoo = Mail::Webmail::Yahoo->new(%options);
  @folders = $yahoo->get_folder_list();
  @messages = $yahoo->get_mail_messages('Inbox', 'all');
  # Write messages to disk here, or do something else.

=head1 DESCRIPTION

This module grew out of the need to download a large archive of web mail in
bulk. As of the module's creation Yahoo did not provide a simple method of
performing bulk operations. 

This module is intended to make up for that shortcoming. 

=head2 METHODS

=over 4

=item $yahoo = new Mail::Webmail::Yahoo(...)

Creates a new Mail::Webmail::Yahoo object. Pass parameters in key => value form,
and these must include, at a minimum:

  username
  password

You may also pass an optional cookie file as cookie_file => '/path/to/file'.	


=item $yahoo->connect();

Connects the application with the site. Really this is not necessary, but it's
in here for hysterical raisins.



=item $yahoo->login();

Mondo method which performs the 'login' stage of connecting to the site. This
method can take a while to complete since there are at least several
re-directs when logging in to Yahoo. 



=item @headers = $yahoo->get_mail_headers($folder, $callback);

***DEPRECATED***

Since this method does exactly what get_mail_messages does, it has been
deprecated and will disappear at some future time. 

Returns an array of message headers for the $folder folder. These are mostly
in Mail::Internet format, which is nice but involves constructing them from what
Yahoo provides -- which ain't much. When an individual message is requested,
we can get more info via turning on the headers, so this method requests each
method in turn (caching for future use, unless cache_messages is turned off)
and builds a Mail::Internet object from each message.

You can get the 'raw' headers from get_folder_index().

Note that for reasons of efficiency both this method and get_mail_messages()
both collect headers and the full text of the message, and this is cached to
avoid having to go back to the network each time. To force a refresh, set the
Snagmail object's cache to 0 with 

  $yahoo->cache_messages(0);
  $yahoo->cache_headers(0);


If $callback is provided it will be called for each header in turn as it is
collected.


=item $page = $yahoo->download_attachment($download_uri, $mailmsg);

Downloads an attachment from the specified uri. $mailmsg is a reference to a
Mail::Internet object.


=item @message_headers = $yahoo->get_folder_index($folder);

Returns a list of all the messages in the specified folder. 


=item @messages = $yahoo->_get_message_links($page)

(Private instance method)

Returns the actual links (as an array) needed to pull down the messages. This
method is used internally and is not intended to be used from applications,
since the messages returned are not in a very friendly form.


=item @folders = $yahoo->get_folder_list();

Returns a list of folders in the account. Logs the user in if not already
done.


=item $resp = $yahoo->_get_a_page($uri, $method, $params);

(Private instance method)

Requests and returns a page found at the specified $uri via the specified
$method. If $params (an arrayref) is present it will be formatted according to
the method. 

If method is empty or undefined, it defaults to GET. The ordering of the
parameters, while seemingly counter-intuitive, allows one of the great virtues
of programming (laziness) by not requiring that the method be passed for every
call.

Returns the response object if no error occurs, otherwise undef.


=back


=head2 EXPORTS

Nothing. The module is intended to be object-based, and functions should
therefore be called using the -> operator. 

=head2 CAVEATS

o  The 'download attachments' feature currently only works for
'multipart/mixed' mime types. This will probably be expanded in a future
version.

o  The user interface of Yahoo webmail is fairly configurable. It is possible
the module may not work out-of-the-box with some configurations. It should,
however, be possible to tweak the settings at the top of the file to allow
conformance to any configuration. 

=head1 AUTHOR

  Simon Drabble  E<lt>sdrabble@cpan.orgE<gt>


=head1 SEE ALSO


=cut



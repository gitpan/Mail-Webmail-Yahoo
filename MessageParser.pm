#  (C)  Simon Drabble 2002
#  sdrabble@cpan.org   10/23/02

#  $Id: MessageParser.pm,v 1.6 2003/01/11 14:03:56 simon Exp $
#

use strict;
use warnings;

package Mail::Webmail::MessageParser;

use base 'HTML::TreeBuilder';

our $VERSION = 0.1;

our $LOOKS_LIKE_A_HEADER = qr{\b[-\w]+:};


our @mail_header_names = qw(
		To From Reply-To Subject
		Date X- Received Content-

);
#		qr{^To}, qr{From}, qr{Reply-To}, qr{Subject},
#		qr{Date}, qr{X-[-\w]+}, qr{Received}, qr{Content-[-\w]+},


# Tags that "shouldn't" appear in the message body.
our $disallow = {
	xbody => 1,
	html  => 1,
	head  => 1,
	meta  => 1,
	xmeta => 1,
	body  => 1,
};



# Fix some crappiness introduced by our fiends in Redmond. 
# These come from the chart at
#   http://www.pemberley.com/janeinfo/latin1.html#unicode
our $ms_to_unicode = {
	"\x82"   => "&#8218",   #    Single Low-9 Quotation Mark
	"\x83"   => "&#402",    #    Latin Small Letter F With Hook
	"\x84"   => "&#8222",   #    Double Low-9 Quotation Mark
	"\x85"   => "&#8230",   #    Horizontal Ellipsis
	"\x86"   => "&#8224",   #    Dagger
	"\x87"   => "&#8225",   #    Double Dagger
	"\x88"   => "&#710",    #    Modifier Letter Circumflex Accent
	"\x89"   => "&#8240",   #    Per Mille Sign
	"\x8a"   => "&#352",    #    Latin Capital Letter S With Caron
	"\x8b"   => "&#8249",   #    Single Left-Pointing Angle Quotation Mark
	"\x8c"   => "&#338",    #    Latin Capital Ligature OE
	"\x91"   => "&#8216",   #    Left Single Quotation Mark
	"\x92"   => "&#8217",   #    Right Single Quotation Mark
	"\x93"   => "&#8220",   #    Left Double Quotation Mark
	"\x94"   => "&#8221",   #    Right Double Quotation Mark
	"\x95"   => "&#8226",   #    Bullet
	"\x96"   => "&#8211",   #    En Dash
	"\x97"   => "&#8212",   #    Em Dash
	"\x98"   => "&#732",    #    Small Tilde
	"\x99"   => "&#8482",   #    Trade Mark Sign
	"\x9a"   => "&#353",    #    Latin Small Letter S With Caron
	"\x9b"   => "&#8250",   #    Single Right-Pointing Angle Quotation Mark
	"\x9c"   => "&#339",    #    Latin Small Ligature OE
	"\x9f"   => "&#376",    #    Latin Capital Letter Y With Diaeresis
};


our $unicode_to_text = {
	"&#8218"   => "'",   #    Single Low-9 Quotation Mark
	"&#402"    => '',    #    Latin Small Letter F With Hook
	"&#8222"   => "'",   #    Double Low-9 Quotation Mark
	"&#8230"   => '..',  #    Horizontal Ellipsis
	"&#8224"   => '',    #    Dagger
	"&#8225"   => '',    #    Double Dagger
	"&#710"    => '',    #    Modifier Letter Circumflex Accent
	"&#8240"   => '',    #    Per Mille Sign
	"&#352"    => '',    #    Latin Capital Letter S With Caron
	"&#8249"   => '<',   #    Single Left-Pointing Angle Quotation Mark
	"&#338"    => 'OE',  #    Latin Capital Ligature OE
	"&#8216"   => '`',   #    Left Single Quotation Mark
	"&#8217"   => "'",   #    Right Single Quotation Mark
	"&#8220"   => '"',   #    Left Double Quotation Mark
	"&#8221"   => '"',   #    Right Double Quotation Mark
	"&#8226"   => 'o',   #    Bullet
	"&#8211"   => '--',  #    En Dash
	"&#8212"   => '---', #    Em Dash
	"&#732"    => '~',   #    Small Tilde
	"&#8482"   => 'TM',  #    Trade Mark Sign
	"&#353"    => '',    #    Latin Small Letter S With Caron
	"&#8250"   => ">",   #    Single Right-Pointing Angle Quotation Mark
	"&#339"    => 'oe',  #    Latin Small Ligature OE
	"&#376"    => '',    #    Latin Capital Letter Y With Diaeresis
};



sub message_start
{
	my ($self, @gubbins) = @_;
	$self->{_message_start} = \@gubbins;
}



sub parse_header
{
	my ($self, $field, $val) = @_;


	my $found = 0;
	if ($field =~ /$LOOKS_LIKE_A_HEADER/) {
		$self->parse($field);
		$self->eof();
		for (@mail_header_names) {
			if ($self->as_text =~ /^($_[^:]*:)/i) {
				$found = $1;
				last;
			}
		}
		if ($found) {
			$self->parse($val);
			$self->eof();
		}
	}
	return $found ? $self->as_trimmed_text : undef;
}





sub parse_body_as_html { parse_body(@_, 'html') }
sub parse_body_as_text { parse_body(@_, 'text') }


# TODO: parameterise/ generalise.
# TODO: allow choice of text/ html
# TODO: allow trimming of yahoo banner/ footer

# TODO: allow content-type: multipart/alternative (check for in headers!)
# $style can be 'html', 'text', or 'both'. Default is 'text'.
# need to check headers for 'content-type: multipart/alternative' to render
# both kinds. For now, assume text and ignore this header.
sub parse_body
{
	my ($self, $html, $style) = @_;

	$self->parse($html);
	$self->eof();

	my $page = new HTML::Element('html');
	my $body = new HTML::Element('body');
	$page->push_content($body);
	my $msg = $self->look_down(@{$self->{_message_start}});
	$body->push_content($msg);

	if ($self->{_debug}) {
		print "sdd 025; ------------------------------------------------\n";
		print $page->as_HTML(undef, "\t");
		print "sdd 026; ------------------------------------------------\n";
		print $page->as_text;
		print "sdd 027; ------------------------------------------------\n";
		$page->dump;
		print "sdd 028; ------------------------------------------------\n";
	}

	my $text = $page->as_text; # as_HTML(undef, "\t"); 
	$text =~ s/^\s*//;
	$text =~ s/\s*$//;
	$text =~ s/$_/$ms_to_unicode->{$_}/g for (keys %$ms_to_unicode);
	if ($text =~ /\&#/) {
# HTML::Entities_decode_entities does not seem to know about chars above 255,
# although Unicode support is claimed in perl > 5.7. So we have to decode
# those ourselves using the ms_to_unicode_to_text tables.
		$text =~ s/$_/$unicode_to_text->{$_}/g for (keys %$unicode_to_text);
	}
	return $text;
}



sub start
{
	my ($self, $tagname, $attr, $attrseq, $origtext) = @_;

# Messages are generally embedded inside a nominally valid HTML doc. Sometimes
# they will have their own html/ body tags - unfortunately, these cause
# HTML::TreeBuilder problems since they are invalid.
	if ($tagname eq 'html') {
		$tagname = 'pre';
		$origtext =~ s/html/pre/g;
	}

	return if exists $disallow->{$tagname};
	$self->SUPER::start($tagname, $attr, $attrseq, $origtext);
}


sub end
{
	my ($self, $tagname) = @_;
	if ($tagname eq 'html') {
		$tagname = 'pre';
	}
	return if exists $disallow->{$tagname};
	shift;
	$self->SUPER::end(@_);
}


1;


__END__


=head1 NAME

Mail::Webmail::MessageParser -- class to parse HTML webmail messages.

=head1 SYNOPSIS

	$p = new Mail::Webmail::MessageParser();
	$p->message_start(_tag => 'div', id => 'message');
	$body_text = $p->parse_body($html, $style);
	while (($field, $data) = each @html_fields_from_somewhere) {
		$header = $p->parse_header($field, $data);
		push @headers, $header if $header;
	}


=head1 DESCRIPTION

Parses header and body HTML and converts both to text, or optionally (for body
text) to simpler fully-formed HTML. 

The package extends HTML::TreeBuilder to include functionality for parsing
email elements from an HTML string.

=head2 METHODS

=over 4

=item $parser->message_start(@message_start_tokens);

Sets the tokens to watch for that denote the beginning of a message. This
allows email messages to be embedded within a DIV or other HTML enclosing tag,
or simple just follow a particular sequence of tags.

The @message_start_tokens array is passed verbatim to the HTML::TreeBuilder/
HTML::Element functions for traversing the HTML tree. This is typically a
list of items such as

  '_tag', 'a', 'href', 'http://foo.bar.com'

which is interpreted to mean "look for an 'anchor' tag with an 'href'
parameter of 'http://foo.bar.com".

Since this is a list or array, I typically use the slightly easier-to-read
notation of

  '_tag' => 'a', 'href' => 'http://foo.bar.com'


=item $hdr_text = $parser->parse_header($field, $data);

Attempts to find a valid Email header name in $field, and a corresponding
value in $data. Potential header names are compared to those in
@mail_header_names iff $field matches the $LOOKS_LIKE_A_HEADER regexp.

If a valid field name is found, the returned string contains the header in the
form 'Name: Value', for example 'To: "A User" <user@server.com>'. If no such
field name is found, undef is returned.

=item $normalised_html = $parser->parse_body_as_html($html);

Convenience method; calls parse_body() with a style of 'html'.

=item $text = $parser->parse_body_as_text($html);

Convenience method; calls parse_body() with a style of 'text'.

=item $text = $parser->parse_body($html, $style);

Returns the parsed message body from $html, using the value passed to
message_start() to determine the beginning of the message. The end of the
message will be the corresponding close tag of the beginning, or the end of
the string if the value passed to message_start() is not a container tag.

The message body returned is converted to normalised HTML (i.e. wrapped in
<html>, <body> tags as appropriate) if $style is 'html'. If $style is empty or
'text', the message body is returned as plain text. Regardless of the style
used, certain character conversions are performed, to remove non-standard
HTML entities such as those introduced by MicroSoft HTML editors. 

=item $parser->start($tagname, $attr, $attrseq, $origtext);
=item $parser->end($tagname);

Override the corresponding methods in HTML::TreeBuilder, which itself
override those in HTML::Parser. These methods should not be called directly
from an application. They are here mainly to remove surplus HTML tags from
around the message body; these tags confuse HTML::TreeBuilder and thus result
in poor behaviour. 


=back


=head2 EXPORTS

Nothing.

=head2 CAVEATS

o  Currently the parse_body() method returns only text. 
o  There may be some issues with the HTML entities being decoded.
o  Message bodies should really be enclosed in container tags; I have not
tested what happens if a non-contained tag is passed to message_start().

=head1 AUTHOR

  Simon Drabble  E<lt>sdrabble@cpan.orgE<gt>

=head1 SEE ALSO

  Mail::Webmail::Yahoo

=cut



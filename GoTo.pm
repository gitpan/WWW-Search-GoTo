#!/usr/local/bin/perl -w

#####################################################
# GoTo.pm
# by Jim Smyser
# Copyright (C) 1996-1999 by Jim Smyser & USC/ISI
# $Id: GoTo.pm,v 1.7 2000/05/16 19:34:43 jims Exp $
######################################################

package WWW::Search::GoTo;

=head1 NAME

WWW::Search::GoTo - class for searching GoTo.com 


=head1 SYNOPSIS

    require WWW::Search;
    $search = new WWW::Search('GoTo');


=head1 DESCRIPTION

This class is an GoTo specialization of WWW::Search.
It handles making and interpreting GoTo searches
F<www-GoTo.com>.

Nothing special about GoTo: no search options. It is much like
Google in that it attempts to returm relavent search results
using simple queries.
 
This class exports no public interface; all interaction should
be done through WWW::Search objects.

=head1 SEE ALSO

To make new back-ends, see L<WWW::Search>.

=head1 HOW DOES IT WORK?

C<native_setup_search> is called before we do anything.
It initializes our private variables (which all begin with underscores)
and sets up a URL to the first results page in C<{_next_url}>.

C<native_retrieve_some> is called (from C<WWW::Search::retrieve_some>)
whenever more hits are needed.  It calls the LWP library
to fetch the page specified by C<{_next_url}>.
It parses this page, appending any search hits it finds to 
C<{cache}>.  If it finds a ``next'' button in the text,
it sets C<{_next_url}> to point to the page for the next
set of results, otherwise it sets it to undef to indicate we're done.

=head1 AUTHOR

C<WWW::Search::GoTo> is written by Jim Smyser
Author e-mail <jsmyser@bigfoot.com>

=head1 COPYRIGHT

Copyright (c) 1996-1999 University of Southern California.
All rights reserved.                                            

THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.


=cut
#'

#####################################################################

require Exporter;
@EXPORT = qw();
@EXPORT_OK = qw();
@ISA = qw(WWW::Search Exporter);
$VERSION = '1.07';

$MAINTAINER = 'Jim Smyser <jsmyser@bigfoot.com>';
$TEST_CASES = <<"ENDTESTCASES";
&test('GoTo', '$MAINTAINER', 'zero', \$bogus_query, \$TEST_EXACTLY);
&test('GoTo', '$MAINTAINER', 'one_page', 'satur'.'nV', \$TEST_RANGE, 1,10);
&test('GoTo', '$MAINTAINER', 'multi', 'iro' . 'ver', \$TEST_GREATER_THAN, 20);
ENDTESTCASES

use Carp ();
use WWW::Search(generic_option);
require WWW::SearchResult;


sub native_setup_search {
       my($self, $native_query, $native_options_ref) = @_;
       $self->{_debug} = $native_options_ref->{'search_debug'};
       $self->{_debug} = 2 if ($native_options_ref->{'search_parse_debug'});
       $self->{_debug} = 0 if (!defined($self->{_debug}));

       #Define default number of hit per page
       $self->{agent_e_mail} = 'jsmyser@bigfoot.com';
       $self->user_agent('user');
       $self->{_next_to_retrieve} = 0;
       if (!defined($self->{_options})) {
       $self->{'search_base_url'} = 'http://www.goto.com';
       $self->{_options} = {
            'search_url' => 'http://www.goto.com/d/search/p/befree/',
            'Keywords' => $native_query,
            };
            }
       my $options_ref = $self->{_options};
       if (defined($native_options_ref)) 
            {
       # Copy in new options.
            foreach (keys %$native_options_ref) 
            {
            $options_ref->{$_} = $native_options_ref->{$_};
            } 
            } 
       # Process the options.
       my($options) = '';
             foreach (sort keys %$options_ref) 
            {
       # printf STDERR "option: $_ is " . $options_ref->{$_} . "\n";
       next if (generic_option($_));
       $options .= $_ . '=' . $options_ref->{$_} . '&';
       }
       chop $options;
       # Finally figure out the url.
       $self->{_next_url} = $self->{_options}{'search_url'} .'?'. $self->hash_to_cgi_string($self->{_options});
       } 

# private
sub native_retrieve_some {
       my ($self) = @_;
       print STDERR "**GoTo::native_retrieve_some()\n" if $self->{_debug};
       
       # Fast exit if already done:
       return undef if (!defined($self->{_next_url}));
       
       # If this is not the first page of results, sleep so as to not
       # overload the server:
       $self->user_agent_delay if 1 < $self->{'_next_to_retrieve'};
       
       # Get some:
       print STDERR "**Requesting (",$self->{_next_url},")\n" if $self->{_debug};
       my($response) = $self->http_request('GET', $self->{_next_url});
       $self->{response} = $response;
       if (!$response->is_success) 
          {
         return undef;
          }
       $self->{'_next_url'} = undef;
       print STDERR "**Found Some\n" if $self->{_debug};
       # parse the output
       my ($HEADER, $HITS, $DESC) = qw(HE HI DE);
       my $state = $HEADER;
       my $hit = ();
       my $hits_found = 0;
       foreach ($self->split_lines($response->content()))
          {
       next if m@^$@; # short circuit for blank lines
       print STDERR " * $state ===$_=== " if 2 <= $self->{'_debug'};

   if ($state eq $HEADER && m|<ol start=\d+>|i) {
       print STDERR "**Beginning Line...\n" ;
       $state = $HITS;
       }
   elsif ($state eq $HITS && m/^<li>.*?<b><a href=(.*)\starget=_top>(.*)<\/a><\/b><br>(.*)<br><em>/i) {
       my ($url, $title,$desc) = ($1,$2,$3);
         if (defined($hit)) 
            {
         push(@{$self->{cache}}, $hit);
            };
       $hit = new WWW::SearchResult;
       $hits_found++;
       $url = "http://goto.com" . $url;
       $hit->add_url($url) if (defined($hit));
       $hit->title($title);
       $hit->description($desc);
       $state = $HITS;
       } 

   elsif ($state eq $HITS && m@<BR><table.*?<a href="(.*)"><.*?>more results</a></td></tr></table>@i) { 
       print STDERR "**Found 'next' Tag\n" if 2 <= $self->{_debug};
       my $sURL = $1;
       $self->{'_next_url'} = $self->{'search_base_url'} . $sURL;
       # print STDERR " **Next Tag is: ", $self->{'_next_url'}, "\n" ;
       $state = $HITS;
          } 
       else 
          {
       print STDERR "**Nothing Matched\n" if 2 <= $self->{_debug};
           }
           } 
       if (defined($hit)) {
           push(@{$self->{cache}}, $hit);
           } 
       return $hits_found;
}
1;




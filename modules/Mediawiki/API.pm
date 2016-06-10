package Mediawiki::API;

use strict;
use Data::Dumper;
use LWP::UserAgent;
use HTTP::Cookies;
use XML::Simple;
use POSIX qw(strftime);
use HTML::Entities;
use Encode;

##########################################################
## Enable a native code XML parser - makes a huge difference
$XML::Simple::PREFERRED_PARSER = "XML::Parser";
# $XML::Simple::PREFERRED_PARSER = "XML::LibXML::SAX";

###########################################################

=pod

Mediawiki::API -Provides methods to access the Mediawiki API via an object 
oriented interface. Attempts be less stupid about errors.

$Revision: 1.32 $

=head1 Synopsis

 $api = Mediawiki::API->new();
 $api->base_url($newurl);
 @list = @{$api->pages_in_category($categoryTitle)};
 $api->edit_page($pageTitle, $pageContent, $editSummary);

=cut

#############################################################3

=head1 Methods

=head2 Initialize the object

=over 

=item $api = Mediawiki::API->new();

Create a new API object

=back

=cut

###

sub new { 
  my $self = {};

  $self->{'agent'} = new LWP::UserAgent;
  $self->{'agent'}->cookie_jar(HTTP::Cookies->new());

  $self->{'baseurl'} = 'https://192.168.1.71/~mw/wiki/api.php';
  $self->{'loggedin'} = 'false';

  ## Configuration parameters
  $self->{'maxlag'} = 5;           # server-side load balancing param 
  $self->{'maxRetryCount'} = 3;    # retries at the HTTP level
  $self->{'debugLevel'} = 1;       # level of verbosity for debug output 
  $self->{'requestCount'} = 0;     # count total HTTP requests
  $self->{'htmlMode'} = 0;         # escape output for CGI output  
  $self->{'debugXML'} = 0;         # print extra debugging for XML parsing
  $self->{'cmsort'} = 'sortkey';   # request this sort order from API
  $self->{'querylimit'} = 500;     # number of results to request per query
  $self->{'botlimit'} = 5000;      # number of results to request if bot
  $self->{'decodeprint'} = 1;      # don't UTF-8 output
  $self->{'xmlretrydelay'} = 10;   # pause after XML level failure 
  $self->{'xmlretrylimit'} = 10;   # retries at XML level

  $self->{'cacheEditToken'} = 0;   

  $self->{'logintries'} = 5;       # delay on login throttle

  bless($self);
  return $self;
}

#############################################################

=head2 Get/set configuration parameters

=over

=item $url = $api->base_url($newurl);

=item $url = $api->base_url();

Set and/or fetch the url of the 
Mediawiki server.  It should be a full URL to api.php on the server.

=cut

sub base_url () { 
  my $self = shift;
  my $newurl = shift;
  if ( defined $newurl)  {
    $self->{'baseurl'} = $newurl;
    $self->print(1, "A Set base URL to: $newurl");
  }

  return $self->{'baseurl'};
}

####################################

=item $level = $api->max_retries($count)

=item $level = $api->max_retries();

Set the number of times to retry the HTTP portion of an API 
request. Retries can also be generated by API responses or
maxlag; this doesn't affect those. 

=cut

sub max_retries  {
  my $self = shift;
  my $count = shift;
  if ( defined $count)  {
    $self->{'maxRetryCount'} = $count;
    $self->print(1, "A Set maximum retry count to: $count");
  }

  return $self->{'maxRetryCount'};
}

########################################################

=item $level = $api->html_mode($new_level)

=item $level = $api->html_mode();

HTML mode - for when the output is passed to a browser. If the level is 
1, output will be in HTML. If the level is 0 (the default), the output 
is in plain text.

=cut

sub html_mode  {
  my $self = shift;
  my $mode = shift;
  if ( defined $mode)  {
    $self->{'htmlMode'} = $mode;
    if ( $self->{'htmlMode'} > 0 ) { 
      $self->print(1, "A Enable HTML mode");
    } else {
      $self->print(1, "A Disable HTML mode");
    }
  }

  return $self->{'htmlMode'};
}

###########################################################

### Internal function, may have no effect depending on debugging code

sub debug_xml  {
  my $self = shift;
  my $mode = shift;
  if ( defined $mode)  {
    $self->{'debugXML'} = $mode;
    if ( $self->{'debugXML'} > 0 ) { 
      $self->print(1, "A Enable XML debug mode");
    } else {
      $self->print(1, "A Disable XML debug mode");
    }
  }

  return $self->{'debugXML'};
}

#######################################################

=item $level = $api->debug_level($newlevel);

=item $level = $api->debug_level();

Set the level of output, from 0 to 5. Level 1 gives minimal feedback, 
level 5 is detailed for debugging.  Intermediate levels give intermediate 
amounts of information.

=cut

sub debug_level { 
 my $self = shift;
 my $level = shift;
 if ( defined $level) { 
   $self->{'debugLevel'} = $level;
   $self->print(1,"A Set debug level to: $level");
 }
 return $self->{'debugLevel'};
}

######################################################

=item $lag = $api->maxlag($newlag)

=item $lag = $api->maxlag()

Get and/or set the maxlag value for requests. 

=cut

sub maxlag { 
  my $self = shift;
  my $maxlag = shift;

  if ( defined $maxlag) { 
    $self->{'maxlag'} = $maxlag;
    $self->print(1,"A Maxlag set to " . $self->{'maxlag'});
  }

  return $self->{'maxlag'};
}

####################################

=item $level = $api->cmsort($order)

=item $level = $api->cmsort();

Set the way that category member lists are sorted when they 
arrive from the server. The $order parmater must be 'timestamp' 
or 'sortkey'.

=cut

sub cmsort  {
  my $self = shift;
  my $order = shift;

  if ( defined $order)  {

    if ( ! ( $order eq 'sortkey' || $order eq 'timestamp') ) { 
      die "cmsort parameter must be 'timestamp' or 'sortkey', not '$order'.\n";
    }

    $self->{'cmsort'} = $order;
    $self->print(1, "A Set category sort order to: $order");
  }

  return $self->{'cmsort'};
}

#############################################################

=head2 Log in

=back

=over

=item $api->login($userName, $password)

Log in to the Mediawiki server, check whether the user has a bot flag, 
and set some defaults appropriately

=back

=cut

sub login { 
 my $self = shift;
 my $userName = shift;
 my $userPassword = shift;
 my $tries = shift || $self->{'logintries'};
 $tries--;

 if (  $tries == 0 ) {
    die "Too many login attempts\n";
 }

 $self->print(1,"A Logging in");

 my $xml  = $self->makeXMLrequest(
                      [ 'action' => 'login', 
                        'format' => 'xml', 
                        'lgname' => $userName, 
                        'lgpassword' => $userPassword  ]);

  if ( ! defined $xml->{'login'} 
       || ! defined $xml->{'login'}->{'result'}) {
    
    $self->print(4, "E no login result.\n" . Dumper($xml));
    $self->handleXMLerror("login err");
  }

  my $result = $xml->{'login'}->{'result'};

  if ( $result ne 'Success' ) {
    if ( $result eq 'Throttled' || $result eq 'NeedToWait') { 
      my $wait = $xml->{'login'}->{'wait'} || 10;
      $self->print(3, "R Login delayed: $result, sleeping " 
                      . (2 + $wait) . " seconds\n");
      $self->print(5, Dumper($xml));

      sleep (2 + $wait);
      return $self->login($userName, $userPassword, $tries);
    }  elsif ( $result eq 'NeedToken' ) {
      my $oldxml = $xml;
         $xml  = $self->makeXMLrequest(
                      [ 'action' => 'login', 
                        'format' => 'xml',
                        'lgname' => $userName,
                        'cookieprefix' => $oldxml->{'login'}->{'cookieprefix'},
                        'sessionid' => $oldxml->{'login'}->{'sessionid'},
                        'lguserid' => $oldxml->{'login'}->{'lguserid'},
                        'lgtoken' => $oldxml->{'login'}->{'token'},
                        'lgpassword' => $userPassword  ]);

       if ( ! defined $xml->{'login'}
         || ! defined $xml->{'login'}->{'result'}) {
              $self->print(4, "E no login result.\n" . Dumper($xml));
              $self->handleXMLerror("login err");
        }

        if ( $xml->{'login'}->{'result'} ne 'Success' ) {
          $self->print(5, "Login error on second phase\n");
          $self->print(5, Dumper($xml));
       }
    } else {
       $self->print(5, "Login error\n");
      $self->print(5, Dumper($xml));
      die( "Login error. Message was: '" . $xml->{'login'}->{'result'} . "'\n");
    }
  }

  $self->print(1,"R Login successful");

  foreach $_ ( 'lgusername', 'lgtoken', 'lguserid' ) { 
    $self->print(5, "I\t" . $_ . " => " . $xml->{'login'}->{$_} );
    $self->{$_} = $xml->{'login'}->{$_};
  }

  $self->{'loggedin'} = 'true';

  if ( $self->is_bot() ) { 
    $self->print (1,"R Logged in user has bot rights");
  }

  delete $self->{'editToken'};

}

##################################

sub login_from_file {
  my $self = shift;
  my $file = shift;
  open IN, "<$file" or die "Can't open file $file: $!\n";

  my ($a, $b, $user, $pass, $o);
  $o = $/;
  $/ = "\n";
  while ( <IN> ) { 
    chomp;
    ($a, $b) = split /\s+/, $_, 2;
    if ( $a eq 'user') { $user = $b;}
    if ( $a eq 'pass') { $pass = $b;}
  }

  close IN;
  $/ = $o;

  if ( ! defined $user ) { 
    die "No username to log in\n";
  }

  if ( ! defined $pass ) { 
    die "No password to log in\n";
  }

  $self->login($user, $pass);

}

#############################################################3

# Internal function

sub cookie_jar {
  my $self = shift;
  return $self->{'agent'}->cookie_jar();
}

#############################################################3


=head2 Edit pages

=over

=item $api->edit_page($pageTitle, $pageContent, $editSummary, $params);

Edit a page. 

The array reference $params allows configuration. Valid parameters listed
at https://www.mediawiki.org/wiki/API:Edit_-_Create%26Edit_pages#Token

Returns undef on success. 
Returns the API.php result hash on error.

=back

=cut

sub edit_page { 
  my $self = shift;
  my $pageTitle = shift;
  my $pageContent = shift;
  my $editSummary = shift;
  my $params = shift || [];

  $self->print(1,"A Editing $pageTitle");

  my $editToken; 

  if ( 1 == $self->{'cacheEditToken'} 
         && defined $self->{'editToken'} ) { 
    $editToken = $self->{'editToken'};
    $self->print(5, "I using cached edit token: $editToken");  
  } else { 
    $editToken = $self->edit_token($pageTitle);
  }

  if ( $editToken eq '+\\' ) { die "Bad edit token!\n"; }

  my $query = 
      [ 'action' => 'edit',
	'token' => $editToken,
	'summary' => $editSummary,
	'text' => $pageContent,
	'title' => $pageTitle,
	'format' => 'xml',
       @$params  ];
  
  my $res  = $self->makeXMLrequest($query);

  $self->print(5, 'R editing response: ' . Dumper($res));

  if ( $res->{'edit'}->{'result'} eq 'Success' ) { 
      return "";
  } else { 
      return $res;
  }

}

############################################################
# internal function

sub edit_token {
  my $self = shift;
  my $pageTitle = shift;

  my $xml  = $self->makeXMLrequest(
                  [ 'action' => 'query', 
                    'prop' => 'info',
                    'titles' => $pageTitle,
                    'intoken' => 'edit',
                    'format' => 'xml']);

  if ( ! defined $xml->{'query'}
       || ! defined $xml->{'query'}->{'pages'}
       || ! defined $xml->{'query'}->{'pages'}->{'page'} 
       || ! defined $xml->{'query'}->{'pages'}->{'page'}->{'edittoken'} ) { 
     $self->handleXMLerror($xml);
  }

  my $editToken = $xml->{'query'}->{'pages'}->{'page'}->{'edittoken'};
  $self->print(5, "R edit token: ... $editToken ...");

  if ( 1 == $self->{'cacheEditToken'} ) { 
    $self->{'editToken'} = $editToken;
    $self->print(5, "I caching edit token");  
  }

  return $editToken;
}

############################################################
# 

=head2 Get lists of pages

=over

=item $articles = 
    $api->pages_in_category($categoryTitle [ , $namespace])

Fetch the list of page titles in a category. Optional numeric
parameter to filter by namespace. Return $articles, an array ref.

=cut

sub pages_in_category {
  my $self = shift;
  my $categoryTitle = shift;
  my $namespace = shift;

  my $results = $self->pages_in_category_detailed($categoryTitle,$namespace);

  my @articles;

  my $result;
  foreach $result (@{$results}) { 
      push @articles, $result->{'title'};
  }

  return \@articles;
}

############################################################
# Compatibility function from old framework

=item $articles = $api->fetch_backlinks_compat($pageTitle)

Fetch list of pages that link to a given page.
Returns $articles as an array reference.

=cut

sub fetch_backlinks_compat {
  my $self = shift;
  my $pageTitle = shift;

  my $results = $self->backlinks($pageTitle);

  my @articles;

  my $result;
  foreach $result (@{$results}) { 
      push @articles, $result->{'title'};
  }

  return \@articles;
}

#############################################################3

=item $pages = $api->backlinks($pageTitle);

Fetch the pages that link to a particular page title.
Returns a reference to an array.

=cut

sub backlinks { 
  my $self = shift;
  my $pageTitle = shift;

  $self->print(1,"A Fetching backlinks for $pageTitle");
 
  my %queryParameters =  ( 'action' => 'query', 
                           'list' => 'backlinks', 
                           'bllimit' => $self->{'querylimit'}, 
#                           'titles' => $pageTitle,
                           'bltitle' => $pageTitle,
                           'format' => 'xml');

  if ( $self->is_bot) { 
    $queryParameters{'bllimit'} = $self->{'botlimit'};
  } 

  my $results 
    = $self->fetchWithContinuation(\%queryParameters, 
                    ['query', 'backlinks', 'bl'],   
                    'bl', 
                    ['query-continue', 'backlinks', 'blcontinue'], 
                    'blcontinue');

  return $results;
}

################################################################

=item $articles = 

$api->pages_in_category_detailed($categoryTitle [, $namespace])

Fetch the contents of a category. Optional parameter to select a  
specific namespace. Returns a reference to an array of hash 
references.

=cut

sub pages_in_category_detailed {
  my $self = shift;
  my $categoryTitle = shift;
  my $namespace = shift;

  $self->print(1,"A Fetching category contents for $categoryTitle");

### The behavior keeps changing with respect to whether 
### the Category: prefix should be included.
  if ( $categoryTitle =~ /^Category:/) { 
#    $self->print(1,"WARNING: Don't pass categories with namespace included");
#    $categoryTitle =~ s/^Category://;
  } else { 
    $categoryTitle = 'Category:' . $categoryTitle;
  }

  my %queryParameters =  ( 'action' => 'query', 
                           'list' => 'categorymembers', 
                           'cmlimit' => $self->{'querylimit'},
                           'cmsort' => $self->{'cmsort'},
                           'cmprop' => 'ids|title|sortkey|timestamp',
                           'cmtitle' => $categoryTitle,
                           'format' => 'xml' );

  if ( defined $namespace ) {
    $queryParameters{'cmnamespace'} = $namespace;
  }

  if ( $self->is_bot) { $queryParameters{'cmlimit'} = $self->{'botlimit'}; }

  my $results 
    = $self->fetchWithContinuation(\%queryParameters, 
                    ['query', 'categorymembers', 'cm'],   
                    'cm', 
                    ['query-continue', 'categorymembers', 'cmcontinue'], 
                    'cmcontinue');

  return $results;
}

#############################################################3

=item $list = $api->where_embedded($templateName);

Fetch the list of pages that tranclude $templateName.
If $templateName refers to a template, it SHOULD start with "Template:".
Returns a reference to an array of hash references.

=cut

sub where_embedded { 
  my $self = shift;
  my $templateTitle = shift;

  $self->print(1,"A Fetching list of pages transcluding $templateTitle");
 
  my %queryParameters =  ( 'action' => 'query', 
                           'list' => 'embeddedin', 
                           'eilimit' => $self->{'querylimit'}, 
                           'eititle' => $templateTitle,
                           'format' => 'xml' );

  if ( $self->is_bot) { 
    $queryParameters{'eilimit'} = $self->{'botlimit'};
  } 

  my $results 
    = $self->fetchWithContinuation(\%queryParameters, 
                    ['query', 'embeddedin', 'ei'],   
                    'ei', 
                    ['query-continue', 'embeddedin', 'eicontinue'],
                    'eicontinue');

  return $results;
}

#############################################################3

=item $list = $api->log_events($pageName, $params);

Fetch a list of log entries for the page.
Returns a reference to an array of hashes.

=cut

sub log_events { 
  my $self = shift;
  my $pageTitle = shift;
  my $params  = shift || [];

  $self->print(1,"A Fetching log events for $pageTitle");
 

  my %queryParameters =  ( 'action' => 'query', 
                           'list' => 'logevents', 
                           'lelimit' => $self->{'querylimit'},
                           'format' => 'xml' ,
                            @$params);

  if ( defined $pageTitle ) { 
    $queryParameters{'letitle'}  = $pageTitle;
  }

  if ( $self->is_bot) { 
    $queryParameters{'lelimit'} = $self->{'botlimit'}
  } 

  my $results 
    = $self->fetchWithContinuation(\%queryParameters, 
                    ['query', 'logevents','item'],   
                    'item', 
                    ['query-continue', 'logevents', 'lestart'],
                    'lestart');

  return $results;
}

#############################################################

=item $list = $api->image_embedded($imageName);

Fetch the list of pages that display the image $imageName.
The value of $imageName should NOT start with "Image:".
Returns a reference to an array of hash references.

=cut

sub image_embedded { 
  my $self = shift;
  my $imageTitle = shift;

  $self->print(1,"A Fetching list of pages displaying image $imageTitle");
 
  my %queryParameters =  ( 'action' => 'query', 
                           'list' => 'imageusage', 
                           'iulimit' => $self->{'querylimit'},
                           'iutitle' => $imageTitle,
                           'format' => 'xml' );

  if ( $self->is_bot) { 
    $queryParameters{'iulimit'} = $self->{'botlimit'};
  } 

  my $results 
    = $self->fetchWithContinuation(\%queryParameters, 
                    ['query', 'imageusage', 'iu'],
                    'iu', 
                    ['query-continue', 'imageusage', 'iucontinue'],
                    'iucontinue');

  return $results;
}
######################################################


######################################################

=item $text = $api->content($pageTitles);

Fetch the content (wikitext) of a page or pages.  $pageTitles
can be either a scalar, in which case it is the title of the page 
to be fetched, or a reference to a list of page titles. If a single
title is passed, the text is returned. If an array reference is passed, 
a hash reference is returned.  

=cut

sub content { 
  my $self = shift;
  my $titles = shift;

  if (ref($titles) eq "") { 
     return $self->content_single($titles);
  }
 
  if ( scalar @$titles == 1) { 
     return $self->content_single(${$titles}[0]);
  }

  $self->print(1,"A Fetching content of " . scalar @$titles . " pages");
 
  my $titlestr = join "|", @$titles;

  my %queryParameters =  ( 'action' => 'query', 
                           'prop' => 'revisions', 
                           'titles' => $titlestr,
                           'rvprop' => 'content',
                           'format' => 'xml' );

  my $results 
    = $self->makeXMLrequest([%queryParameters]);

  my $arr = {};
  my $data = $self->child_data($results, ['query', 'pages', 'page']);

  my $result;

  foreach $result ( @$data) { 
    $arr->{$result->{'title'}} = $result->{'revisions'}->{'rev'}->{'content'};
  }

  return $arr;
}
 
#########################################################

## Internal function

sub content_single { 
  my $self = shift;
  my $pageTitle = shift;

  $self->print(1,"A Fetching content of $pageTitle");
 
  my %queryParameters =  ( 'action' => 'query', 
                           'prop' => 'revisions', 
                           'titles' => $pageTitle,
                           'rvprop' => 'content',
                           'format' => 'xml' );

  my $results 
    = $self->makeXMLrequest([%queryParameters]);

  return $self->child_data_if_defined($results, 
                       ['query', 'pages', 'page', 'revisions', 'rev','content'], '');
}
#########################################################

=item $text = $api->content_section($pageTitle, $secNum);

Fetch the content (wikitext) of a particular section of a page.
The lede section is #0. 

=cut

sub content_section { 
  my $self = shift;
  my $pageTitle = shift;
  my $section = shift;

  if ( ! ( $section =~ /^\d+$/ ) ) { 
    die "Bad section: '$section'. Must be a nonnegative integer.\n";
  }

  $self->print(1,"A Fetching content of $pageTitle");
 
  my %queryParameters =  ( 'action' => 'query', 
                           'prop' => 'revisions', 
                           'titles' => $pageTitle,
                           'rvprop' => 'content',
                           'rvsection' => $section,
                           'format' => 'xml' );
  my $results 
    = $self->makeXMLrequest([%queryParameters]);

  return $self->child_data_if_defined($results, 
                       ['query', 'pages', 'page', 'revisions', 'rev'], '');
}


###################################################

=item $text = $api->revisions($pageTitle, $count);

Fetch the most recent $count revisions of a page.

=cut

sub revisions {
  my $self = shift;
  my $title = shift;

  my $count = shift;
  if ( ! defined $count ) { 
    $count = $self->{'querylimit'};
  }

  my $what = "ids|flags|timestamp|size|comment|user";
 
  my $data = $self->makeXMLrequest([ 'format' => 'xml',
                                       'action' => 'query',
                                       'prop' => 'revisions',
                                       'rvprop' => $what,
                                       'rvlimit' => $count,
                                       'titles' => encode("utf8", $title)  ], 
                                     [ 'page', 'rev' ]);

  my $t = $self->child_data_if_defined($data, ['query','pages','page']);
  return $self->child_data_if_defined(${$t}[0], ['revisions', 'rev']);
}



################################################################

=item $info = $api->page_info($page);

Fetch information about a page. Returns a reference to a hash. 

=cut

sub page_info {
  my $self = shift;
  my $pageTitle = shift;

  $self->print(1,"A Fetching info for $pageTitle");

  my $what = 'protection|talkid|subjectid'; 

  my %queryParameters =  ( 'action' => 'query', 
                           'prop' => 'info',
                           'inprop' => $what,
                           'titles' => $pageTitle,
                           'format' => 'xml' );

  my $results 
    = $self->makeXMLrequest([%queryParameters]);

  return $self->child_data($results,  ['query', 'pages', 'page']);
}

#######################################################

# Internal Function

sub fetchWithContinuation {
  my $self = shift;
  my $queryParameters = shift;
  my $dataPath = shift;
  my $dataName = shift;
  my $continuationPath = shift;
  my $continuationName = shift;
  
  $self->add_maxlag_param($queryParameters);

  $self->print(5, "I Query parameters:\n" . Dumper($queryParameters));

  my $xml = $self->makeXMLrequest([ %{$queryParameters}], [$dataName]);
  my @results = @{$self->child_data_if_defined($xml, $dataPath, [])};

#  $self->print(6, Dumper($xml));

  while ( defined $xml->{'query-continue'} ) { 
    $self->print(5, "CONTINUE: " . Dumper($xml->{'query-continue'}));

    $queryParameters->{$continuationName} =     
	encode("utf8",$self->child_data( $xml, $continuationPath,
                                     "Error in categorymembers xml"));
    $xml =$self->makeXMLrequest([ %{$queryParameters}], [$dataName]);
    @results = (@results, 
                @{$self->child_data_if_defined($xml, $dataPath, [])} );

  }

  return \@results;
}

#######################################################
# Internal function

sub add_maxlag_param {
  my $self = shift;
  my $hash = shift;

  if ( defined $self->{'maxlag'} && $self->{'maxlag'} >= 0 ) { 
    $hash->{'maxlag'} = $self->{'maxlag'}
  }
}

#############################################################3

=item $contribs = $api->user_contribs($userName);

Fetch the list of nondeleted edits by a user. Returns a 
reference to an array of hash references.

=cut

sub user_contribs { 
  my $self = shift;
  my $userName = shift;
  my @results;
  $self->print(1,"A Fetching contribs for $userName");

  my %queryParameters =  ( 'action' => 'query', 
                           'list' => 'usercontribs', 
                           'uclimit' => $self->{'querylimit'},
                           'ucdirection' => 'older',
                           'ucuser' => $userName,
                           'format' => 'xml' ); 

  if ( $self->is_bot) { 
    $queryParameters{'uclimit'} = $self->{'botlimit'};
  } 

  $self->add_maxlag_param(\%queryParameters);

  my $res  = $self->makeHTTPrequest([ %queryParameters ]);
  
  my $xml = $self->parse_xml($res);

  @results =  @{$self->child_data( $xml, ['query', 'usercontribs', 'item'],  
                                          "Error in usercontribs xml")};

  while ( defined $xml->{'query-continue'} ) { 
    $queryParameters{'ucstart'} = 
            $self->child_data( $xml, ['query-continue', 'usercontribs', 'ucstart'],
                               "Error in usercontribs xml");

    $self->print(3, "I Continue from: " . $xml->{'query-continue'}->{'usercontribs'}->{'ucstart'} );

    $res  = $self->makeHTTPrequest([%queryParameters]);

    $xml = $self->parse_xml($res);

    @results = ( @results, 
                 @{$self->child_data( $xml, ['query', 'usercontribs', 'item'],                                                 
                                      "Error in usercontribs xml")});
  }

  return \@results;
}

######################3

=item $api->parse( $wikitext ) 

Parse a chunk of wiki code and return the HTML result. 

=cut

sub parse { 
  my $self = shift;
  my $content = shift;

  my $r = $self->makeXMLrequest(['action'=>'parse',
                                 'text'=>encode('utf8', $content),
                                 'format' => 'xml']);

  return $self->child_data($r, ['parse']);
}                                  


#############################################################3

=back

=head2 Information about the logged in user

=over

=item $api->watchlist($limit, $window);

Fetch list of pages on the user's watchlist that have been 
recently edited.   Numeric parameters: $limit is maximum number
of pages to return, $window is number of hours of history to fetch. 

=cut

sub watchlist { 
 my $self = shift;

 $self->print(1,"A Fetching watchlist entries");

 my $timeStamp; 

 my $limit = shift;
 my $window = shift;

 if ( ! defined $limit) { 
   $limit = 100;
 } 

 if ( ! defined $window) { 
   $window = 24;
 }

 $self->print(2,"I Maximum result count: $limit\n");
 $self->print(2,"I Time window for entries: $window\n");

 my $delay = $window * 60 * 60; # window is in hours
 $timeStamp = strftime('%Y-%m-%dT%H:%M:00Z', gmtime(time() - $delay));

 my $xml  = $self->makeXMLrequest(
                  [ 'action' => 'query', 
                    'list' => 'watchlist', 
                    'wllimit' => $limit,
                    'wlprop' =>  'ids|title|timestamp|user|comment|flags',
                    'wlend' => $timeStamp,      
                    'format' => 'xml'  ]);

  if ( ! defined $xml->{'query'}
       || ! defined $xml->{'query'}->{'watchlist'}
       || ! defined $xml->{'query'}->{'watchlist'}->{'item'} ) { 
     $self->handleXMLerror($xml);
  }

#  return $xml->{'query'}->{'watchlist'}->{'item'};
   return $self->child_data($xml, ['query','watchlist','item']);
}

#############################################################3

=item $properties = $api->user_properties();

Fetch the properties the server reports for the logged in 
user.  Returns a references to an array.

=cut

sub user_properties { 
  my $self = shift;
  my @results;
  $self->print(1,"A Fetching information about logged in user");

  my %queryParameters =  ( 'action' => 'query', 
                           'meta' => 'userinfo', 
                           'uiprop' => 'rights|hasmsg',
                           'format' => 'xml' ); 

  $self->add_maxlag_param(\%queryParameters);

  my $xml  = $self->makeXMLrequest([ %queryParameters ]);

  return $self->child_data($xml,['query','userinfo']);
}

##############################################################

=item $info = $api->site_info();

Fetch information about the MediaWiki site (namespaces,
main page, etc.)

=cut

sub site_info { 
  my $self = shift;
  my @results;
  $self->print(1,"A Fetching information mediawiki site");

  my %queryParameters =  ( 'action' => 'query', 
                           'meta' => 'siteinfo', 
                           'siprop' => 'general|namespaces|statistics|interwikimap|dbrepllag',
                           'format' => 'xml' ); 

  $self->add_maxlag_param(\%queryParameters);

  my $xml  = $self->makeXMLrequest([ %queryParameters ]);

  return $self->child_data($xml,['query']);
}

##############################################################

=item $rights = $api->user_rights();

Fetch the rights (flags) the server reports for the logged 
in user.  Returns a reference to an array of rights.

=cut


sub user_rights {
   my $self = shift;
   my $r = $self->user_properties();
   return $self->child_data($r, ['rights','r']);
}

#############################################################


=item $api->user_is_bot()

Returns nonzero if the logged in user has the 'bot' flag

=cut

sub user_is_bot {
  my $self = shift;
  my $rights = $self->user_rights();

  my $r;
  foreach $r ( @{$rights}) { 
    if ( $r eq 'bot') { 
      return 1;
    }
  }
  return 0;
}

#############################################################3

=back 

=head2 Advanced usage and internal functions

=over

=item $api->makeXMLrequest($queryArgs [ , $arrayNames])

Makes a request to the server, parses the result, and
attempts to detect errors from the API and retry. 

Optional parameter $arrayNames is used for the 'ForceArray' 
parameter of XML::Simple.

=cut

sub makeXMLrequest {  
  my $self = shift;
  my $args = shift;
  my $arrayNames = shift;

  my $retryCount = 0;

  my $edelay = $self->{'xmlretrydelay'};

  my $res;
  my $xml;

  while (1) { 
    $retryCount++;
    if ( $retryCount > $self->{'xmlretrylimit'} ) {
      die "Aborting: too many retries in getXMLrequest\n";
    }
   

    $res = $self->makeHTTPrequest($args);
  
    $self->print(7, "Got result\n$res\n---\n");

    if ( length $res == 0) { 
      $self->print(1,"E Error: empty XML response");
      $self->print(2,"I Query params: \n" . Dumper($args));
      $self->print(2,"I ... sleeping $edelay seconds");
      sleep $edelay;
      next;
    }

    eval {  
      if ( defined $arrayNames ) { 
        $xml = $self->parse_xml($res, 'ForceArray', $arrayNames);
      } else { 
        $xml = $self->parse_xml($res);
      } 
    };

    if ( $@ ) { 
      $self->print(3, "Error parsing XML - truncated response?");
      $self->print(3, Dumper($@));
      sleep $edelay;
      next;
    }

    $self->print(6, "XML dump:");
    $self->print(6, Dumper($xml));

    last if ( ! defined $xml->{'error'} );

    if ( $xml->{'error'}->{'code'} eq 'maxlag') { 
      $xml->{'error'}->{'info'} =~ /: (\d+) seconds/;
      my $lag = $1;
      if ($lag > 0) { 
        $self->print(2,"E Maximum server lag exceeded");
        $self->print(3,"I Current lag $lag, limit " . $self->{'maxlag'});
      }
      sleep $lag + 1;
      $retryCount--; # this is not an error
      next;
    }

    $self->print(2,"E APR response indicates error");
    $self->print(3, "Err: " . $xml->{'error'} ->{'code'});
    $self->print(4, "Info: " . $xml->{'error'} ->{'info'});
    $self->print(4, "Details: " . Dumper($xml) . "\n");
    sleep $edelay;
  }

#  return decode_recursive($xml);
return $xml;
}

######################################

=item $api->makeHTTPrequest($args)

Makes an HTTP request and returns the resulting content. This is the 
most low-level access to the server. It provides error detection and 
automatically retries failed attempts as appropriate. Most queries will 
use a more specific method.

The $args parameter must be a reference to an array of KEY => VALUE 
pairs. These are passed directly to the HTTP POST request.

=cut

sub makeHTTPrequest {
  my $self = shift;
  my $args = shift;

#  $self->{'requestCount'}++;

  my $retryCount = 0;
  my $delay = 4;

  my $res;

  while (1) { 
    $self->{'requestCount'}++;

    if ( $retryCount == 0) { 
      $self->print(2, "A  Making HTTP request (" . $self->{'requestCount'} . ")");
      $self->print(5, "I  Base URL: " . $self->{'baseurl'});
      my $k = 0;
      while ( $k < scalar @{$args}) { 
        if ( ! defined ${$args}[$k+1] ) { ${$args}[$k+1] = ''; }
        $self->print(5, "I\t" . ${$args}[$k] . " => '" 
                       . ${$args}[$k+1] . "'");
        $k += 2;
      }

    } else { 
      $self->print(1,"A  Repeating request ($retryCount)");
    }

    $res = $self->{'agent'}->post($self->{'baseurl'}, $args);
    last if $res->is_success();

#    print Dumper($res);

    $self->print(1, "HTTP response code: " . $res->code() ) ;
    $self->print(5, "Dump of response: " . Dumper($res) );  


    if (defined $res->header('x-squid-error')) { 
      $self->print(1,"I  Squid error: " . $res->header('x-squid-error'));
    }

    $retryCount++;

    $self->print(3, "I  Sleeping for " . $delay . " seconds");

    sleep $delay;
    $delay = $delay * 2;
     
    if ( $retryCount > $self->{'maxRetryCount'}) { 
      my $errorString = 
           "Exceeded maximum number of tries for a single request.\n";
      $errorString .= 
       "Final HTTP error code was " . $res->code() . " " . $res->message . "\n";
      $errorString .= "Aborting.\n";
      die($errorString);
    }
  }

  return $res->content();
}


##############################################################
# Internal function

sub child_data_is_defined { 
  my $self = shift;
  my $p = shift;
  my @r = @{shift()};

  my $name;
  foreach $name ( @r) { 
    if ( ! defined $p->{$name})  {	
      return 0;
    }
  }
  return 1;
}

################################################################

# Internal function

sub child_data { 
  my $self = shift;
  my $p = shift;
  my @r = @{shift()};
  my $errorMsg = shift;

  my $name;
  foreach $name ( @r) { 
    if ( ! defined $p->{$name}) { 
        $self->handleXMLerror($p, "$errorMsg; child '$name' not defined");
    }
    $p = $p->{$name}
  }

  return $p;
}

sub child_data_if_defined { 
  my $self = shift;
  my $p = shift;
  my @r = @{shift()};
  my $default = shift;

  my $name;
  foreach $name ( @r) { 
    if ( ! defined $p->{$name}) { 
        return $default;
    }
    $p = $p->{$name}
  }

  return $p;
}

###################################

# Internal function

sub print {
  my $self = shift;
  my $limit = shift;
  my $message = shift;

  if ( $self->{'decodeprint'} == 1) {
    $message = decode("utf8", $message);
  }

  if ( $limit <= $self->{'debugLevel'} ) {
    print $message;
    if ( $self->{'htmlMode'} > 0) {
      print " <br/>\n";
    } else {
      print "\n";
    }
  }
}

#############################################################

# Internal method

sub dump { 
  my $self = shift;
  return Dumper($self);
}


#############################################################3

# Internal function

sub handleXMLerror { 
  my $self = shift;
  my $xml = shift;
  my $text =  shift;

  my $error = "XML error";

  if ( defined $text) { 
    $error = $error . ": " . $text;
  }

  print Dumper($xml);

  die "$error\n";
}
######################################3

### Recursively decode entities from the XML data structure

sub decode_recursive {
  my $data = shift;
  my $newdata;
  my $i;

  if ( ref($data) eq "" ) { 
#    return decode_entities($data);
     return undo_htmlspecialchars($data);
  } 

  if ( ref($data) eq "SCALAR") { 
#    $newdata = decode_entities($$data);
    $newdata = undo_htmlspecialchars($$data);
    return \$newdata;
  } elsif ( ref($data) eq "ARRAY" ) { 
    $newdata = [];
    foreach $i ( @$data) {
      push @$newdata, decode_recursive($i);
    }
    return $newdata;
  } elsif ( ref($data) eq "HASH") { 
    $newdata = {};
    foreach $i ( keys %$data ) {
      $newdata->{decode_recursive($i)} = decode_recursive($data->{$i});
    }
    return $newdata;
  }

  die "Bad value $data\n";
}



#######################################################

# Internal function

sub is_bot { 
  my $self = shift;

  if ( ! defined $self->{'isbot'} )  { 
    if ( $self->user_is_bot() ) {
      $self->{'isbot'} = "true";
    } else { 
      $self->{'isbot'} = "false";
    }
  }

  return ( $self->{'isbot'} eq 'true');
}


#############################################################3
# Internal function

sub parse_xml {
  my $self = shift;
  if ( $self->debug_xml() > 0) { 
    print "DEBUG_XML Parsing at " . time() . "\n";
  }
  my $xml;

  #  The API may return XML that is not valid UTF-8
  my $t = decode("utf8", $_[0]);
  $_[0] = encode("UTF-8", $t);  # this is secret code for strict UTF-8

  eval { 
   $xml = XML::Simple::parse_string(@_);
  };
  if ( $@ ) { 
    print "XML PARSING ERROR 1\n";
#    print "Code: $! \n";
# not well-formed (invalid token)
    print Dumper(@_);
    die;
  }

  if ( $self->debug_xml() > 0) { 
    print "DEBUG_XML Finish parsing at " . time() . "\n";
  }

  return $xml;
}

##############################################
# internal function

sub undo_htmlspecialchars  {
  my $text = shift;
  my %trans = ( '&amp;' => '&', 
                '&quot;' => '"', 
                '&#039;' => '\'', 
                '&lt;' => '<', 
                '&gt;' => '>' );
  my $tran;
  foreach $tran ( keys %trans ) { 
    $text =~ s/\Q$tran\E/$trans{$tran}/g;
  } 
  return $text;
}

###############################3
# Close POD

=back

=head1 Copryright

Copyright 2008 by Carl Beckhorn. 

Released under GNU Public License (GPL) 2.0.

=cut


########################################################
## Return success upon loading class
1;

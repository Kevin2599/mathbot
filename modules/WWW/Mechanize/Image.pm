package WWW::Mechanize::Image;
# vi:et:sw=4 ts=4

use strict;
use warnings;

=head1 NAME

WWW::Mechanize::Image - Image object for WWW::Mechanize

=head1 SYNOPSIS

Image object to encapsulate all the stuff that Mech needs

=head1 Constructor

=head2 new()

Creates and returns a new C<WWW::Mechanize::Image> object.

    my $image = WWW::Mechanize::Image->new( {
        url    => $url,
        base   => $base,
        tag    => $tag,
        name   => $name,    # From the INPUT tag
        height => $height,  # optional
        width  => $width,   # optional
        alt    => $alt,     # optional
    } );

=cut

sub new {
    my $class = shift;
    my $parms = shift || {};

    my $self = {};

    for my $parm ( qw( url base tag height width alt name ) ) {
        $self->{$parm} = $parms->{$parm} if defined $parms->{$parm};
    }

    return bless $self, $class;
}

=head1 Accessors

=head2 $link->url()

URL from the link

=head2 $link->base()

Base URL to which the links are relative.

=head2 $link->name()

Name for the field from the NAME attribute, if any.

=head2 $link->tag()

Tag name (either "image" or "input")

=head2 $link->height()

Image height

=head2 $link->width()

Image width

=head2 $link->alt()

ALT attribute from the source tag, if any.

=cut

sub url     { return ($_[0])->{url}; }
sub base    { return ($_[0])->{base}; }
sub name    { return ($_[0])->{name}; }
sub tag     { return ($_[0])->{tag}; }
sub height  { return ($_[0])->{height}; }
sub width   { return ($_[0])->{width}; }
sub alt     { return ($_[0])->{alt}; }

=head2 $link->URI()

Returns the URL as a L<URI::URL> object.

=cut

sub URI {
    my $self = shift;

    require URI::URL;
    my $URI = URI::URL->new( $self->url, $self->base );

    return $URI;
}

=head2 $link->url_abs()

Returns the URL as an absolute URL string.

=cut

sub url_abs {
    my $self = shift;

    return $self->URI->abs;
}

=head1 COPYRIGHT

Copyright (c) 2004 Andy Lester. All rights reserved. This program is
free software; you can redistribute it and/or modify it under the same
terms as Perl itself.

=cut

1;

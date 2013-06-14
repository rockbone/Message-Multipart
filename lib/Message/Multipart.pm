package Message::Multipart;

use utf8;
use Carp;
use Encode;
use MIME::QuotedPrint;
use MIME::Base64;
use Net::SMTP;
use Message::Multipart::MIME qw/%MIME/;

$Message::Multipart::VERSION = "0.01";

our $MIME_VERSION = "1.0";
our $Content_Transfer_Encoding = "7bit";

our %MULTI_PART = (
    'multipart/mixed'       => 'multipart/mixed',
    'mixed'                 => 'multipart/mixed',
    'multipart/alternative' => 'multipart/alternative',
    'alternative' => 'multipart/alternative',
    'multipart/parallel'    => 'multipart/parallel',
    'parallel'    => 'multipart/parallel'
);

our %ENCODING = (
    "7bit"             => "7bit",
    "8bit"             => "8bit",
    "quoted-printable" => "quoted-printable",
    "qp"               => "quoted-printable",
    "base64"           => "base64"
);

our %DISPOSITION = (
    "inline"     => "inline",
    "attachment" => "attachment"
);

our @BOUNDARIES; # to make unique boundary

sub new {
    my ( $class,$type ) = @_;
    croak "Multipart subtype is required\n" if !$type;
    croak "Unknown subtype $type\n" if !$MULTI_PART{lc $type};
    return bless { multipart_type => $MULTI_PART{lc $type} }, ref $class || $class;
}

sub part {
    my ( $self,%arg ) = @_;
    my $content_type = $MIME{lc $arg{content_type}} || $MULTI_PART{lc $arg{content_type}}
        or croak "Unknown content-type [$arg{content_type}]\n";
    my $content_encoding = $ENCODING{lc $arg{content_encoding}}
        or croak "Unknown encoding [$arg{content_encoding}]\n";
    my $content_disposition = $DISPOSITION{lc $arg{content_disposition}} || "";
    my $file_name = $arg{file_name} || "";
    my $charset = $arg{charset} || '';
    my $content = $charset ? encode( $charset,$arg{content} ) : $arg{content};
    if ( $content_encoding eq "quoted-printable" ){
        $content = encode_qp( $content );
    }
    elsif ( $content_encoding eq "base64" ){
        $content = encode_base64( $content );
    }
    my $part = {
        content_type        => $content_type,
        content_encoding    => $content_encoding,
        content             => $content,
    };
    $part->{charset}             = $charset if $charset;
    $part->{content_disposition} = $content_disposition if $content_disposition;
    $part->{file_name}           = $file_name if $file_name;
    push @{ $self->{multipart} },$part;
}

sub from {
    my ( $self,@from ) = @_;
    if ( @from ){
        push @{ $self->{from} },$_ for @from;
    }
    return wantarray ? @{ $self->{from} } : $self->{from};
}

sub to {
    my ( $self,@to ) = @_;
    if ( @to ){
        push @{ $self->{to} },$_ for @to;
    }
    return wantarray ? @{ $self->{to} } : $self->{to};
}

sub cc {
    my ( $self,@cc ) = @_;
    if ( @cc ){
        push @{ $self->{cc} },$_ for @cc;
    }
    return wantarray ? @{ $self->{cc} } : $self->{cc};
}

sub bcc {
    my ( $self,@bcc ) = @_;
    if ( @bcc ){
        push @{ $self->{bcc} },$_ for @bcc;
    }
    return wantarray ? @{ $self->{bcc} } : $self->{bcc};
}

sub subject {
    my ( $self,$subject ) = @_;
    if ( $subject ){
        $self->{subject} = encode( 'MIME-Header-ISO_2022_JP',$subject );
    }
    return $self->{subject};
}

sub as_string {
    my $self = shift;
    use Data::Dumper;
    my $boundary = $self->boundary;
    my $string;
    for my $addr ( qw/from to cc bcc/ ){
        if ( $self->$addr ){
            $string .= ucfirst( $addr ).": ".join( ",",$self->$addr )."\n";
        }
    }
    $string .= "Subject: ".$self->subject."\n" if $self->subject;
    $string .= <<EOF;
MIME-Version: $MIME_VERSION
Content-Type: @{ [ $self->{multipart_type} ] };boundary="$boundary"
Content-Transfer-Encoding: $Content_Transfer_Encoding

EOF
    while ( my $part = shift @{ $self->{multipart} } ){
        my $content_type = $part->{charset} && $part->{file_name} ? $part->{content_type}.q{;charset="}.$part->{charset}.q{;name="}.$part->{file_name}.q{"}
                         : $part->{charset} ? $part->{content_type}.q{;charset="}.$part->{charset}.q{"}
                         : $part->{file_name} ? $part->{content_type}.q{;name="}.$part->{file_name}.q{"}
                         : $part->{content_type};
        my $content_disposition = $part->{content_disposition} && $part->{file_name} ? $part->{content_disposition}.q{;filename="}.$part->{file_name}.q{"}
                                : $part->{content_disposition} ? $part->{content_disposition}
                                : q{};
        # header
        $string .= <<EOF;
--$boundary
Content-Type: $content_type
Content-Transfer-Encoding: @{ [ $part->{content_encoding} ] }
EOF
        $string .= "Content-Disposition: $content_disposition" if $content_disposition;
        
        # content
        $string .= <<EOF;

@{ [ $part->{content} ] }
EOF
    }
    $string .= "--$boundary--";
    return $string;
}

sub send {
    my $self = shift;
    my $smtp = Net::SMTP->new('localhost')
        or croak "Failed to Connect local mailserver\n";
    local $@;
    #eval {
        $smtp->mail( $self->from  )
            or die;
        $smtp->recipient( $self->to )
            or die;
        if ( @{ $self->cc } ){
            $smtp->cc( $self->cc )
                or die;
        }
        if ( @{ $self->bcc } ){
            $smtp->bcc( $self->bcc )
                or die;
        }
        $smtp->data
            or die;
        $smtp->datasend( $self->as_string )
            or die;
        $smtp->dataend
            or die;
        $smtp->quit
            or die;
    #};
    return 0 if $@;
    return 1;
}

sub boundary {
    my $self = shift;
    return if $self->{boundary};
    my $new_boundary;
    my @strings = ("a".."z","A".."Z",0..9,"_");
    while ( 1 ){
        for ( 1..36 ){
            $new_boundary .= $strings[ int( rand( $#strings + 1) ) ];
        }
        last if !grep{ $new_boundary eq $_ }@BOUNDARIES;
        $new_boundary = '';
    }
    push @BOUNDARIES,$new_boundary;
    $self->{boundary} = $new_boundary;
    return $self->{boundary};
}
1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Message::Multipart - making and sending multipart message

=head1 DESCRIPTION

This module can create multipart message.Also can send it.

=head1 SYNOPSIS

    use utf8;
    use Message::Multipart;

    my $m = Message::Multipart->new( 'alternative' );
    $m->part(
        content_type        => 'plain',
        content_encoding    => '7bit',
        charset             => 'ISO-2022-jp',
        content             => $content
    );
    $m->part(
        content_type        => 'html',
        content_encoding    => 'qp',
        charset             => 'utf8',
        content             => $html
    );
    $m->from( 'mail_from@example.com' );
    $m->to( 'mail_to1@example.com','mail_to2@example.com' );
    $m->cc( 'mail_cc@example.com' );
    $m->bcc( 'mail_bcc@example.com' );
    $m->send;

=head1 METHOD

=head2 $m = Message::Multipart->new

    require multipart subtype as argument.
        subtypes are...
            'mixed'
            'alternative'
            'parallel'

=head2 $m->part

    arguments are...
        content_type        => content type         # required
        content_encoding    => content encoding     # required
        content             => content of its part  # required
        charset             => charset of its part  # optional
        content_disposition => inline or attachment # optional
        file_name           => file name            # optional

    content must be 'utf8'(internal character encoding of Perl).
    'part' method automatically encode it the charset you set.

=head2 $m->from

=head2 $m->to

=head2 $m->cc

=head2 $m->bcc

    one or more mail address list

=head2 $m->as_string

    return as string its multipart

=head2 $m->send

    sending mail with local mail server

=head2 $child = $m->new

    it can nest multipart in multipart

    $m->part(
        content_type        => 'multipart/mixed',
        content_encoding    => '7bit',
        content             => $child->as_string
    );

=head1 AUTHOR

Tooru Iwsaki < rockbone.g{at}gmail.com >

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2013 by Tooru Iwasaki

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

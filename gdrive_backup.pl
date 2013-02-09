#!/usr/bin/env perl

=head1 NAME

gdrive_backup - Command line tool to upload a document to Google Docs using serialized OAuth token.

=head1 USAGE

    gdrive_backup -d <doc name to save to> -s <source file to backup> [-c <configuration file>] [ -f <MIME type> ] [-h]

Requires a source file (to upload), and a filename to use on Google Docs. If a doc with this name exists, it will be replaced.

You have to authorize the app as well, with create_token.pl. 

=head1 OPTIONS

=head2 -f

Allows you to specify a MIME type for the document. Default is I<text/plain>.

=cut

use 5.10.0;

use strict;
use warnings;

use Net::OAuth2::Profile::WebServer;
use Data::Dumper;
use JSON;
use Getopt::Long;
use Pod::Usage;
use Path::Tiny;
use YAML::Any qw/ LoadFile /;

#Describes the OAuth server to authenticate to
my $server_config_file = "gdrive_backup.conf";

GetOptions( "config|c=s"   =>   \$server_config_file,
            "source|s=s"   =>   \my $source_file,
            "doc|d=s"      =>   \my $target_doc,
            "filetype|f=s" =>   \my $file_type,
            "help|h!"    =>     \my $help,
            'man!'       =>     \my $man,
) or pod2usage( -verbose => 0 );

pod2usage( -verbose => 1 ) if $help;
pod2usage( -verbose => 2 ) if $man;


my $server_config = LoadFile($server_config_file);

my $server = Net::OAuth2::Profile::WebServer->new(
    %{$server_config->{'oauth_conf'}},
    access_type=>'offline',
);

#The credentials for OAuth
my $access_token = $server->create_access_token(
    decode_json( path($server_config->{token_file})->slurp )
);

$server->update_access_token($access_token);

my $document_id = get_document_id( $access_token, $target_doc );

upload_document( $access_token, $document_id, $file_type, $source_file );

exit;

###### utility functions #################################

sub upload_document {
    my( $access_token, $document_id, $file_type, $source_file ) = @_;

    my $resp = $access_token->put(
        "https://www.googleapis.com/upload/drive/v2/files/$document_id?uploadType=media&convert=true",
        ['Content-Type'=>$file_type],
        path($source_file)->slurp
    );

    die "Failed to upload, HTTP error ".$resp->code unless $resp->code == 200;

    say "$source_file uploaded as $target_doc";
}

sub get_document_id {
    my( $access_token, $target_doc ) = @_;

    my $resp = $access_token->get("https://www.googleapis.com/drive/v2/files?q=title='$target_doc'");

    die 'Got HTTP error listing documents', $resp->code unless $resp->code == 200;

    my $existing_docs = decode_json($resp->content);

    return $existing_docs->{'items'}[0]{id} if @{$existing_docs->{items}};

    $resp = $access_token->post("https://www.googleapis.com/drive/v2/files/",
        ['Content-Type'=>'application/json'],
        encode_json({'title'=> $target_doc})
    );

    die "Failed to create file, HTTP error ".$resp->code unless $resp->code == 200;

    return decode_json($resp->content)->{id};
}


#!/usr/bin/perl
use strict;
use warnings;
use lib qw(/home/amjoh11/lib);

use Carp;
use Data::Dumper;
use MIME::Base64;
use MSA::CommonFunctions qw(file_slurp);


my $file_name = shift @ARGV;
my $data = file_slurp($file_name);
#print $data, "\n";
$data = MIME::Base64::decode($data);
print $data, "\n\n";
my $key_name = 'local_masque';
my $cipher = do
{
	my $key;
	{
		# prevent tainting error
		local $ENV{'PATH'} = '';
		$key = `/usr/bin/$key_name`;
	}
	Crypt::CBC->new(
		-key	=> $key,
		-cipher	=> 'Crypt::OpenSSL::AES',
	);
};

my $text = $cipher->decrypt($data);
print "$text\n\n";

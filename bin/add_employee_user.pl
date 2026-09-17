#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long qw(GetOptions);
use JSON::PP qw(decode_json encode_json);
use Net::LDAP;
use Net::LDAPS;
use Net::LDAP::Constant qw(LDAP_ALREADY_EXISTS LDAP_NO_SUCH_ATTRIBUTE);
use Net::LDAP::Entry;
use Net::LDAP::Extension::SetPassword;

my $LDAP_HOST     = 'localhost';
my $LDAP_PORT     = 389;
my $ADMIN_DN      = 'cn=admin,dc=msaint';
my $EMPLOYEES_OU  = 'ou=employees,ou=users,dc=msaint';
my $DEFAULT_EMAIL = 'test.dev@multiserviceaviation.com';
my $DEFAULT_FROM  = 'test.dev@multiserviceaviation.com';
my $SECRET_ID     = 'local_ldap_server';
my $LDAP_TIMEOUT  = 15;
my $LDAPS_PORT    = 636;
my $SSL_CHAIN_CERT = $ENV{MSA_CHAIN_CERT_FN} // '/etc/ssl/certs/msaint_chain_ca.crt';

my %opts = (
    host      => $LDAP_HOST,
    port      => $LDAP_PORT,
    email     => $DEFAULT_EMAIL,
    from      => $DEFAULT_FROM,
    secret_id => $SECRET_ID,
    timeout   => $LDAP_TIMEOUT,
);

GetOptions(
    'first-name|f=s' => \$opts{first_name},
    'last-name|l=s'  => \$opts{last_name},
    'email|e=s'      => \$opts{email},
    'from-email=s'   => \$opts{from},
    'host=s'         => \$opts{host},
    'port=i'         => \$opts{port},
    'timeout=i'      => \$opts{timeout},
    'secret-id=s'    => \$opts{secret_id},
    'help|h'         => \$opts{help},
) or usage(1);

usage(0) if $opts{help};

for my $required (qw(first_name last_name)) {
    if ( !defined $opts{$required} || $opts{$required} eq q{} ) {
        usage(1);
    }
}

my $given_name = normalize_name( $opts{first_name} );
my $surname    = normalize_name( $opts{last_name} );
my $cn         = "$given_name $surname";
my $uid        = build_uid( $given_name, $surname );
my $dn         = "uid=$uid,$EMPLOYEES_OU";
my $password   = generate_password(14);
progress("Reading AWS secret $opts{secret_id}");
my $secret     = get_secret( $opts{secret_id} );
my $bind_dn    = $secret->{admin_user} // $secret->{bind_dn} // $secret->{dn} // $secret->{username} // $secret->{user} // $ADMIN_DN;
my $admin_pwd  = $secret->{admin_password};
my $aws_region = $secret->{region};
my $secret_host = $secret->{host};
my $secret_port = $secret->{port};

die "Secret $opts{secret_id} does not contain an LDAP password\n" if !defined $admin_pwd || $admin_pwd eq q{};

my @ldap_targets = (
    {
        host => $opts{host},
        port => $opts{port},
    },
);

if (
    defined $secret_host
    && $secret_host ne q{}
    && defined $secret_port
    && $secret_port =~ /\A\d+\z/
    && !( $secret_host eq $opts{host} && $secret_port == $opts{port} )
) {
    push @ldap_targets, {
        host => $secret_host,
        port => $secret_port,
    };
}

my $ldap = connect_ldap( \@ldap_targets, $opts{timeout} );

progress("Binding to LDAP as $bind_dn");
my $mesg = $ldap->bind( $bind_dn, password => $admin_pwd );
die "LDAP bind failed: " . $mesg->error . "\n" if $mesg->code;

progress("Reading password policy from $EMPLOYEES_OU");
my $policy_dn = get_ou_policy( $ldap, $EMPLOYEES_OU );

my $user_created = 0;

progress("Creating LDAP entry $dn");
$mesg = $ldap->add(
    Net::LDAP::Entry->new($dn)->add(
        objectClass       => [qw(top person organizationalPerson inetOrgPerson)],
        uid               => $uid,
        cn                => $cn,
        sn                => $surname,
        givenName         => $given_name,
        mail              => $opts{email},
        pwdPolicySubentry => $policy_dn,
    )
);

if ( $mesg->code ) {
    if ( $mesg->code == LDAP_ALREADY_EXISTS ) {
        progress("User already exists; resetting password for $dn");
    }
    else {
        die "LDAP add failed: " . $mesg->error . "\n";
    }
}
else {
    $user_created = 1;
}

progress("Setting password for $dn");
$mesg = $ldap->set_password(
    user      => $dn,
    newpasswd => $password,
);
die "Password set failed for $dn: " . $mesg->error . "\n" if $mesg->code;

progress("Clearing pwdReset for $dn");
$mesg = $ldap->modify(
    $dn,
    delete => { pwdReset => [] },
);

if ( $mesg->code && $mesg->code != LDAP_NO_SUCH_ATTRIBUTE ) {
    die "Clearing pwdReset failed for $dn: " . $mesg->error . "\n";
}

progress("Sending password email to $opts{email} via SES");
my $email_error = eval {
    send_password_email(
        to       => $opts{email},
        from     => $opts{from},
        region   => $aws_region,
        uid      => $uid,
        name     => $cn,
        password => $password,
    );
    return;
};

$email_error = $@ if $@;

progress("Unbinding from LDAP");
$ldap->unbind;

print <<"EOT";
@{[ $user_created ? 'Created employee user' : 'Reset employee user password' ]}
DN: $dn
UID: $uid
Name: $cn
Email: $opts{email}
Password: $password
Password Policy: $policy_dn
EOT

if ($email_error) {
    chomp $email_error;
    print "Email Status: FAILED\n";
    print "Email Error: $email_error\n";
}
else {
    print "Email Status: SENT\n";
}

sub progress {
    my ($message) = @_;

    print "[add_employee_user] $message\n";

    return;
}

sub connect_ldap {
    my ( $targets, $timeout ) = @_;

    my @errors;

    for my $target ( @{$targets} ) {
        progress("Connecting to LDAP at $target->{host}:$target->{port} (timeout ${timeout}s)");

        my $ldap;
        if ( $target->{port} == $LDAPS_PORT ) {
            $ldap = Net::LDAPS->new(
                $target->{host},
                scheme  => 'ldaps',
                port    => $target->{port},
                timeout => $timeout,
                inet4   => 1,
                version => 3,
                verify  => 1,
                cafile  => $SSL_CHAIN_CERT,
            );
        }
        else {
            $ldap = Net::LDAP->new(
                $target->{host},
                port    => $target->{port},
                timeout => $timeout,
            );
        }

        if ($ldap) {
            return $ldap;
        }

        push @errors,
            sprintf(
                '%s:%s: %s',
                $target->{host},
                $target->{port},
                $@ || 'connection failed',
            );
    }

    die "Cannot connect to any LDAP server:\n" . join( "\n", @errors ) . "\n";
}

sub send_password_email {
    my (%args) = @_;

    my $region = $args{region};
    die "Secret $opts{secret_id} does not contain an AWS region for SES\n"
        if !defined $region || $region eq q{};

    my $subject = sprintf 'Your MSA LDAP account for %s', $args{name};
    my $body = <<"EOBODY";
Hello $args{name},

Your LDAP account has been created.

UID: $args{uid}
Email: $args{to}
Temporary password: $args{password}

Please store this password securely.
EOBODY

    my $payload = encode_json(
        {
            FromEmailAddress => $args{from},
            Destination      => {
                ToAddresses => [ $args{to} ],
            },
            Content => {
                Simple => {
                    Subject => {
                        Data    => $subject,
                        Charset => 'UTF-8',
                    },
                    Body => {
                        Text => {
                            Data    => $body,
                            Charset => 'UTF-8',
                        },
                    },
                },
            },
        }
    );

    my $cmd = sprintf(
        q{aws sesv2 send-email --region %s --cli-input-json %s 2>&1},
        shell_quote($region),
        shell_quote($payload),
    );
    my $output = qx{$cmd};
    my $exit_code = $? >> 8;

    die "Failed to send password email to $args{to}: $output\n" if $exit_code != 0;
}

sub get_secret {
    my ($secret_id) = @_;

    my $cmd = sprintf(
        q{aws secretsmanager get-secret-value --secret-id %s --query SecretString --output text 2>&1},
        shell_quote($secret_id),
    );
    my $output = qx{$cmd};
    my $exit_code = $? >> 8;

    die "Failed to read AWS secret $secret_id: $output\n" if $exit_code != 0;
    die "AWS secret $secret_id has no SecretString\n" if !defined $output || $output =~ /\A(?:None)?\s*\z/;

    chomp $output;

    my $secret = eval { decode_json($output) };
    die "AWS secret $secret_id does not contain valid JSON\n" if !$secret || ref $secret ne 'HASH';

    if ( exists $secret->{$secret_id} && ref $secret->{$secret_id} eq 'HASH' ) {
        $secret = $secret->{$secret_id};
    }

    return $secret;
}

sub get_ou_policy {
    my ( $ldap, $ou_dn ) = @_;

    my $search = $ldap->search(
        base   => $ou_dn,
        scope  => 'base',
        filter => '(objectClass=organizationalUnit)',
        attrs  => ['pwdPolicySubentry'],
    );

    die "Failed to read OU policy from $ou_dn: " . $search->error . "\n"
        if $search->code;

    my ($entry) = $search->entries;
    die "OU not found: $ou_dn\n" if !$entry;

    my $policy_dn = $entry->get_value('pwdPolicySubentry');
    die "OU $ou_dn has no pwdPolicySubentry attribute\n" if !$policy_dn;

    return $policy_dn;
}

sub build_uid {
    my ( $first_name, $last_name ) = @_;

    my $first = lc substr( collapse_for_uid($first_name), 0, 1 );
    my $last  = lc substr( collapse_for_uid($last_name), 0, 6 );

    die "Unable to derive uid from supplied name\n" if $first eq q{} || $last eq q{};

    return $first . $last;
}

sub collapse_for_uid {
    my ($value) = @_;

    $value =~ s/[^A-Za-z0-9]//g;

    return $value;
}

sub normalize_name {
    my ($value) = @_;

    $value =~ s/^\s+//;
    $value =~ s/\s+$//;

    die "Name value cannot be empty\n" if $value eq q{};

    return $value;
}

sub generate_password {
    my ($length) = @_;

    my @upper  = ('A' .. 'Z');
    my @lower  = ('a' .. 'z');
    my @digits = ('0' .. '9');
    my @all    = ( @upper, @lower, @digits );

    die "Password length must be at least 3\n" if $length < 3;

    my @password = (
        $upper[ random_index( scalar @upper ) ],
        $lower[ random_index( scalar @lower ) ],
        $digits[ random_index( scalar @digits ) ],
    );

    while ( @password < $length ) {
        push @password, $all[ random_index( scalar @all ) ];
    }

    @password = shuffle(@password);

    return join q{}, @password;
}

sub random_index {
    my ($size) = @_;

    return int( rand($size) );
}

sub shuffle {
    my @items = @_;

    for ( my $i = @items - 1 ; $i > 0 ; $i-- ) {
        my $j = int( rand( $i + 1 ) );
        @items[ $i, $j ] = @items[ $j, $i ];
    }

    return @items;
}

sub shell_quote {
    my ($value) = @_;

    $value =~ s/'/'"'"'/g;

    return "'$value'";
}

sub usage {
    my ($exit_code) = @_;

    print <<"EOUSAGE";
Usage:
  ./add_employee_user.pl --first-name FIRST --last-name LAST [--email EMAIL]
                         [--from-email EMAIL] [--host HOST] [--port PORT]
                         [--timeout SECONDS]
                         [--secret-id SECRET_ID]

Creates a user under $EMPLOYEES_OU.
UID format: first letter of first name + first 6 letters of last name.
Email defaults to: $DEFAULT_EMAIL
From address defaults to: $DEFAULT_FROM
LDAP timeout defaults to: $LDAP_TIMEOUT seconds

LDAP bind credentials are read from AWS Secrets Manager secret: $SECRET_ID
EOUSAGE

    exit $exit_code;
}

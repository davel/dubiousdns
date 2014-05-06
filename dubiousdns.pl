#!/usr/bin/perl

use strict;
use warnings;

use YAML qw/ LoadFile /;
use FindBin;

use LWP::UserAgent;
use Socket;

my $config = LoadFile("$FindBin::Bin/config.yaml");

my $our_ip = get_local_ip();
my $old_ip;

# To avoid hitting the twittertubes more than necessary, cache the last
# written IP address in a file.
if (open(my $fh, "<", $config->{ip_filename})) {
    $old_ip = <$fh>;
    chomp $old_ip;

    # Don't trust cache is older (or newer!) than a day
    if (abs(-M $fh)>1) {
        warn "Ignoring cache once a day";
        $old_ip = undef;
    }
    # Don't trust remembered value unless we can delete it
    if (unlink($config->{ip_filename})!=1) {
        warn "We can't delete cache, not distrusting: $!";
        $old_ip = undef;
    }
}

if (!defined($old_ip)) {
    my $packed_ip = gethostbyname($config->{hostname});
    if (defined($packed_ip)) {
        $old_ip = inet_ntoa($packed_ip);
    }
}

if ($old_ip ne $our_ip) {
    warn "updating dns to $our_ip from $old_ip";
    open(my $fh, "-|", "nsupdate", "-k", "$FindBin::Bin/".$config->{key}) or die $!;
    print $fh "server ".$config->{server}."\n";
    print $fh "zone ".$config->{zone}."\n";
    print $fh "update delete ".$config->{hostname}."\n";
    print $fh "update add ".$config->{hostname}. " ".$config->{ttl}." $our_ip\n";
    print $fh "send\n";
    close $fh;
}

open(my $fh, ">", $config->{ip_filename}) or die $!;
print $fh "$our_ip\n";
close $fh;
exit 0;
   

sub get_local_ip {
    my $router_ip = $config->{router_ip};
    my $ua = LWP::UserAgent->new();
    $ua->credentials("$router_ip:80", "NETGEAR WNDR4500", $config->{router_user}, $config->{router_pass});

    my $res = $ua->get("http://$router_ip/BAS_ether.htm");

    my $data = $res->content;

    my $our_ip;

    if ($res->is_success && $data =~ /<INPUT name=wan_ipaddr type=hidden value=\s+\"(\d+\.\d+\.\d+\.\d+)\">/) {
        $our_ip = $1;
    }
    else {
        warn $res->status_line."\n";
        warn $data;
        die "Failed to get external IP address";
    }
    $res = $ua->get("http://$router_ip/LGO_logout.htm");
    unless ($res->is_success) {
        warn $res->status_line."\n";
    }
    return $our_ip;
}

#!/usr/bin/env perl

use 5.010;
use Data::Dumper;

# http://unix.stackexchange.com/questions/199164/error-run-lvm-lvmetad-socket-connect-failed-no-such-file-or-directory-but
#system("systemctl enable lvm2-lvmetad.service && systemctl enable lvm2-lvmetad.socket && systemctl start lvm2-lvmetad.service && systemctl start lvm2-lvmetad.socket");

my $mount_point =  sub {
    my $path = shift;
    my( %m, $dfh )= ();
    for(`df -h $path`){ chomp; $dfh = $_ unless $_ =~ /^Filesystem/ }
    ( $m{filesystem}, $m{size}, $m{used}, $m{avail}, $m{used_perc}, $m{mountpoint})  = split(/\s+/, $dfh);
    ( $m{vg}, $m{lv} ) = split(" ", `lvs $m{filesystem} --noheadings -o vg_name,lv_name`);

    my @pv = ();
    open my $p,'-|',"pvs -a";
    while( <$p> ){
        if(/(\/.*?) .*?($m{vg})/){ 
            chomp $1; push @pv, $1;
        }
    }
    $m{pv} = \@pv; close $p;
    $m{disk} = $m{pv}->[0]; $m{disk} =~ s/[0-9]+//g;
    return \%m;
};
#
##my @opt = qw< p n p t 2 w 8e w >;

sub extend {
    my $m = $mount_point->(shift);
    #print Dumper $m; #test
    my $extend = <<"_448";
        echo "n
        n
        1


        "|fdisk $m->{disk}

_448

    system("$extend");
}

extend("$ARGV[0]");

=head1 non-interactive fdisk
#!/bin/sh
hdd="/dev/hda /dev/hdb /dev/hdc"
for i in $hdd;do
echo "n
p
1


w
"|fdisk $i;mkfs.ext3 $i;done 
=cut

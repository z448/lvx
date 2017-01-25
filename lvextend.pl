#!/usr/bin/env perl

use 5.010;
use Data::Dumper;

# http://unix.stackexchange.com/questions/199164/error-run-lvm-lvmetad-socket-connect-failed-no-such-file-or-directory-but
system("systemctl enable lvm2-lvmetad.service && systemctl enable lvm2-lvmetad.socket && systemctl start lvm2-lvmetad.service && systemctl start lvm2-lvmetad.socket");

sub conf {
    my $param = shift;
    my $conf = {
        filesystem  =>  sub{
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
            return \%m;
        },
    };
    return $conf->{$param} if defined $conf->{$param};
};

##my @opt = qw< p n p t 2 w 8e w >;
my $f = conf('filesystem');
print Dumper($f->($ARGV[0]));


=head1 on ubuntu 16.04 do
=cut








__DATA__
NAME                               MAJ:MIN RM   SIZE RO TYPE MOUNTPOINT
fd0                                  2:0    1     4K  0 disk
sda                                  8:0    0    16G  0 disk
├─sda1                              8:1    0   500M  0 part /boot
└─sda2                               8:2    0  15.5G  0 part
  ├─vg_iprepository-lv_root (dm-0) 254:0    0  13.6G  0 lvm  /
  └─vg_iprepository-lv_swap (dm-1) 254:1    0     2G  0 lvm  [SWAP]
sdb                                  8:16   0   150G  0 disk
└─sdb1                               8:17   0   117G  0 part
  └─vg_repodata-lv_big (dm-2)      254:2    0   117G  0 lvm  /big
sr0                                 11:0    1  1024M  0 rom
repository:~#


root@ubuntu:~/Documents/perls# lsblk
NAME                  MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
sda                     8:0    0   60G  0 disk
├─sda1                  8:1    0   48G  0 part /
├─sda3                  8:3    0  5.9G  0 part
└─sda5                  8:5    0    2G  0 part [SWAP]
sdb                     8:16   0    5G  0 disk
└─sdb1                  8:17   0  2.4G  0 part
  ├─vg_repodata-lvol0 252:0    0  1.2G  0 lvm
  └─vg_repodata-lvol1 252:1    0  1.2G  0 lvm
sr0                    11:0    1 1024M  0 rom


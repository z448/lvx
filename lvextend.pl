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

---------o
# http://unix.stackexchange.com/questions/238939/how-to-mount-a-logical-volume

root@ubuntu:~# mkfs.ext4 /dev/vg_repodata/lvol0
mke2fs 1.42.13 (17-May-2015)
Creating filesystem with 307200 4k blocks and 76800 inodes
Filesystem UUID: 8366f180-48a5-46b0-8cda-9a4f02abd7c8
Superblock backups stored on blocks:
        32768, 98304, 163840, 229376, 294912

Allocating group tables: done
Writing inode tables: done
Creating journal (8192 blocks): done
Writing superblocks and filesystem accounting information: done

root@ubuntu:~# mkdir /big
root@ubuntu:~# mount $LV_NAME /data
mount: can't find /data in /etc/fstab
root@ubuntu:~# mount /dev/vg_repodata/lvol0 /big
root@ubuntu:~# df -h
Filesystem                     Size  Used Avail Use% Mounted on
udev                           973M     0  973M   0% /dev
tmpfs                          199M   12M  187M   6% /run
/dev/sda1                       48G  4.7G   41G  11% /
tmpfs                          992M  2.4M  990M   1% /dev/shm
tmpfs                          5.0M  4.0K  5.0M   1% /run/lock
tmpfs                          992M     0  992M   0% /sys/fs/cgroup
tmpfs                          199M   76K  199M   1% /run/user/1000
/dev/sda3                      5.7G   12M  5.4G   1% /media/zdenek/38b3dc33-2987-46ca-a3eb-aa5cf31cbf9f
/dev/mapper/vg_repodata-lvol0  1.2G  1.8M  1.1G   1% /big



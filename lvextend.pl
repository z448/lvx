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

my $extend = sub {
	my $path = shift;
    	my $m = $mount_point->($path);
    	print Dumper $m; #test
	#my $p = qq{echo -e "n\n\n\n\nt\n8e\nw\n" |fdisk $m->{disk}};
	#system("partprobe $m->{disk}");

	my @pv = @{ $m->{pv} };
	my $last_pv = $pv[$#pv]; 
	my $new_pv = $last_pv;
	$new_pv =~ /(.*?)([0-9]).*/;
	my($pv, $nr) = ($1, $2); $nr++; $pv = $pv . $nr;
	say $pv;
	#system("pvcreate $pv");
	#system("vgextend $m->{vg} $m->{$pv}");
	#system("lvextend -l +100% $m->{}");
	#system("resize2fs /dev/vg_repodata/lv_big");
};

my $e = $extend->("$ARGV[0]");





__DATA__

create partition sdb1 for full current space 5G
initialize pv to use with lvm (pvcreate /dev/sdb1)
create lv vg on sdb1 full extend to disk size(5G) (vgcreate vg_repodata /dev/sdb1; lvcreate -n lv_big -l 100%FREE vg_repodata)
make filesystem type (mkfs.ext4 /dev/vg_repodata/lv_big)
mount lv to mountpoint (mount /dev/vg_repodata/lv_big /big)

----
extend disk in vm to 7G

sdb                      8:16   0    7G  0 disk
└─sdb1                   8:17   0    5G  0 part
  └─vg_repodata-lv_big 252:0    0    5G  0 lvm
----

create partition sdb2 for remainging space 2G
initialize pv to use with lvm (pvcreate /dev/sdb2)
force kernel to use new part table (partprobe /dev/sdb)
Add this pv to vg_tecmint vg to extend the size of a volume group to get more space for expanding lv(vgextend vg_tecmint /dev/sda2)
check available Physical Extends( available Physical Extend )
expand lv(lvextend -l +4607 /dev/vg_repodata/lv_big)
resize fs (resize2fs /dev/vg_repodata/lv_big)

create lv vg on sdb2 full extend (2G)
???check fstype(df -T /big)
???make filesystem type (mkfs.ext4 /dev/vg_repodata/lv_big)



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

#!/usr/bin/env perl

use 5.010;
use warnings;
use strict;

use Data::Dumper;
use File::Path qw( mkpath );
use Getopt::Std;

my $opt = {};
getopts('n:e:', $opt);

my $map = sub {
    my( $path, $size ) = @_;
    my( %m, @m )= ();

    my $dfh = `df -h $path`;
    die "mountpoint $path doesnt exist" unless $dfh =~ /.*/;

    open(my $fh,'<', \$dfh);
    while(<$fh>){
        chomp; next if $_ =~ /Filesystem/;
        ( $m{lv_path}, $m{size}, $m{used}, $m{avail}, $m{used_perc}, $m{mountpoint})  = split(/\s+/, $_);
        %m = () and next unless $m{mountpoint} eq $path;
        say "###$m{mountpoint}";
        ( $m{vg}, $m{lv} ) = split(" ", `lvs $m{lv_path} --noheadings -o vg_name,lv_name`);

        my @pv = ();
        open my $p,'-|',"pvs -a";
        while( <$p> ){
            if(/(\/.*?) .*?($m{vg})/){ 
                chomp $1; push @pv, $1;
            }
        }

        $m{pv} = \@pv; close $p;
        $m{disk} = $m{pv}->[0]; $m{disk} =~ s/[0-9]+//g;

        open $p,'-|',"lsblk -dnl $m{disk} --output SIZE";
        chomp( $m{disk_size} = <$p> ); close $p;

        open $p,'-|',"lsblk -dnl $m{lv_path} --output SIZE";
        chomp( $m{lv_size} = <$p> ); close $p;

        $m{pv_next} = $m{disk} . ($#pv + 2);
        $m{pv_last} = $#pv + 1;
                                          #--
        $m{fdisk_seq} = ["n\n","\n","\n","\n","\n","t\n","\n","8e\n","\n","w\n"]; 
        $m{fdisk_seq}->[4] = "$size\n" if defined $size;
    }
    return \%m;
};

my $create_part = sub {
	my $m = shift;
    open my $psss,'>&',STDOUT;
    open STDOUT,'+>', undef;
	open my $p,'|-', "fdisk $m->{disk}" ;
    for( @{$m->{fdisk_seq}} ){ print $p $_ };
	close $p;
	system("partprobe $m->{disk}");
    open STDOUT,'>&',$psss;
	system("pvcreate $m->{pv_next}");
	system("vgextend $m->{vg} $m->{pv_next}");

};

my $lv_extend = sub {
    my $m = shift;
    system("lvextend -l +100%FREE /dev/$m->{vg}/$m->{lv}");
	system("resize2fs /dev/$m->{vg}/$m->{lv}");
};

my $lvm = sub {
    my( $path, $size ) = @_;
    my $dfh = `df -h $path`; chomp $dfh;
    die if $dfh !~ /$path/;
    if( defined $size and $size !~ /^\+[0-9]+(K|M|G|T|P)$/){ die system("perldoc $0") }

    my $m = $map->( $path, $size);
    #say Dumper $m;
    die "cant create more LVM partitions on $m->{disk}" if $m->{pv_last} == 4;
    if( $m->{disk_size} eq $m->{lv_size} ){ say Dumper $m and die "$m->{lv} size same as $m->{disk} size, nothing to do" }
    else { $create_part->($m,$size); sleep 1; say $lv_extend->($m); say `lsblk` }
};

my $lv_exist = sub {
    my( $name, $type) = @_;
    my $cmd = $type . 's';
    open my $p,'-|', "$cmd --noheadings $name";
    my $exist = <$p>;
    close $p;
    if($exist){
        $exist =~ s/\s+(.*?)\s+(.*?)\s.*/$1$2/;
        #return $1;
        return $2 if $name eq $1;
    }
};

my $lv_new = sub {
    my($disk, $vg, $lv, $path, $size) = @_;

    mkpath($path) unless -d $path;

    # create partition if $disk ends with number
    my $fdisk = sub {
        my $part = shift;
        my $disk = $part; $disk =~ s/[0-9]//g;
        my $fdisk_seq = ["n\n","\n","\n","\n","\n","t\n","\n","8e\n","\n","w\n"]; 
        $fdisk_seq->[4] = "$size\n" if defined $size;
        open my $p,'|-', "fdisk $disk" ;
        for( @{$fdisk_seq} ){ print $p $_ };
        close $p;
        system("partprobe $disk");
    };

    #my $lve = $lv_exist->($lv,'lv');
    #my $vge = $lv_exist->($vg,'vg');
    #die "$lv belongs to $vg" unless $vg eq $lv_exist->($lv,'lv');
    $fdisk->($disk) if $disk =~ /[0-9]$/;

    system("pvcreate $disk") unless $lv_exist->($disk,'pv');

    my $p = {
        vg  =>  sub{ 
                    my $v = "vgextend $vg $disk" if $lv_exist->($vg,'vg');
                    $v = "vgcreate $vg $disk" unless $lv_exist->($vg,'vg');
                    return $v;
                },
        lv  =>  sub{
                    if($lv_exist->($lv,'lv')){ 
                        #if( $vg not $lv_exist->($lv,'lv') ){ die "$lv belongs to $vg" };
                        return "lvextend -l 100%FREE /dev/$vg/$lv && resize2fs /dev/$vg/$lv";
                    } else {
                        return "lvcreate -n $lv -l 100%FREE $vg && mkfs.ext4 /dev/$vg/$lv";
                    }
                },
        };

        #say "######## system(" . $p->{vg}->() . ")";
        #say "######## system(" . $p->{lv}->() . ")";
        system($p->{vg}->() && $p->{lv}->());
        system("mount /dev/$vg/$lv $path");


                    
                        
=head1
        if( $lv_exist->($vg,'vg') ){ 
            system("vgextend $vg $disk")
            system("lvextend -L $size /dev/$vg/$lv");
        system("resize2fs /dev/$vg/$lv");
        
        system("vgcreate $vg $disk");
        system("lvcreate -n $lv -l 100%FREE $vg");
        system("mkfs.ext4 /dev/$vg/$lv");
=cut



};


#my $e = $lv_exist->("vg_repodata","vg"); if($e){ print $e }; die; #test

#die system("perldoc $0") unless @ARGV;
say "####" . $lv_exist->('lv_nuc','lv');die;
if(defined $opt->{n}){
    my @new = split(',',$opt->{n});
    my $disk = $new[0]; $disk =~ s/[0-9]//g;
    die "$new[0] doesnt exist" unless -b $disk;
    die "cant create partition om $new[0], disk is assigned to $lv_exist->($new[0],'pv')" if $lv_exist->($new[0],'pv');
    $lv_new->(@new);
    my $m = $map->('/big');
    say Dumper $m;
    die;
} elsif(defined $opt->{e}) {
    my @extend = split(',',$opt->{e});
    die "cant create partition om $extend[0], disk is assigned to $lv_exist->($extend[0],'pv')" if $lv_exist->($extend[0],'pv');
    $lvm->(@extend);
}




=head1 NAME 

lvextender - extend existing lv

=head1 USAGE

Extend lv mounted on /dir to full size of disk

C<lvextender /dir>

Extend lv mounted on /dir by 3G

C<lvextender /dir +3G>

=cut



__DATA__

in VMWare add new disk 5G
reboot linux
lsblk will show new disk with NAME sdc (if sda and sdb exist.. every new disk uses next letter in alphabet as last letter )

create partition sdc1 for full current space 5G (fdisk /dev/sdc)
initialize pv to use with lvm (pvcreate /dev/sdc1)
create vg and add /dev/sdc1 partition (vgcreate vg_repodata /dev/sdc1;
create lv on sdc1 full extend to disk size(5G) and add it in vg  (lvcreate -n lv_big -l 100%FREE vg_repodata)
make filesystem type (mkfs.ext4 /dev/vg_repodata/lv_big)
mount lv to mountpoint (mount /dev/vg_repodata/lv_big /big)
put in /etc/fstab (/dev/vg_repodata/lv_big /big ext4 defaults 0 1)

OTHER COMMANDS
remove PV
- first remove PV frmom VG (vgreduce vg_repodata /dev/sdb3)
- then remove PV from LVM (pvremove /dev/sdb3)

if doesnt work

- remove partition fdisk /dev/sdb
- remove PV (vgreduce --removemissing --force vg_repodata)

----
extend disk in vm to 7G

sdc                      8:16   0    7G  0 disk
└─sdc1                   8:17   0    5G  0 part
  └─vg_repodata-lv_big 252:0    0    5G  0 lvm
----

create partition sdc2 for remainging space 2G
initialize pv to use with lvm (pvcreate /dev/sdc2)
force kernel to use new part table (partprobe /dev/sdc)
Add this pv to vg_tecmint vg to extend the size of a volume group to get more space for expanding lv(vgextend vg_tecmint /dev/sda2)
check available Physical Extends( available Physical Extend )
expand lv(lvextend -l +4607 /dev/vg_repodata/lv_big)
resize fs (resize2fs /dev/vg_repodata/lv_big)

create lv vg on sdc2 full extend (2G)
???check fstype(df -T /big)
???make filesystem type (mkfs.ext4 /dev/vg_repodata/lv_big)

# http://unix.stackexchange.com/questions/199164/error-run-lvm-lvmetad-socket-connect-failed-no-such-file-or-directory-but
#system("systemctl enable lvm2-lvmetad.service && systemctl enable lvm2-lvmetad.socket && systemctl start lvm2-lvmetad.service && systemctl start lvm2-lvmetad.socket");

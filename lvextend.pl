#!/usr/bin/env perl

use 5.010;
use warnings;
use strict;

use Data::Dumper;
use File::Path qw( mkpath );
use Getopt::Std;

use Test::Simple tests => 3;

my $opt = {};
getopts('n:e:', $opt);


# take $disk name ('sda'); return  hashref of exsisting (not only LVM) partitions..
my $get_part = sub {
    my( $disk ) = @_;
    my( @p ) = ();
    return unless -b "/dev/$disk";

    open my $pipe,'-|',"fdisk -l /dev/$disk";
    while(<$pipe>){ 
        chomp; next unless $_ =~ /^\/dev\//;
        if(/(^\/.*?[0-9]+) .* (.*)$/){ 
            my %p = ();
            $p{path} = $1;
            $p{type} = $2;
            push @p, {%p}; 
        }
    }; 
    close $pipe;
    return \@p;
};

# take $dir (/dir), optional $size ('+1G') return hashref with its $fs,$vg,$lv,%$disk
my $get_dir = sub {
    my( $dir, $size ) = @_;
    my( %m, @m )= ();

    open my $pipe,"-|","df -h $dir";
    while(<$pipe>){
        next if $_ =~ /Filesystem/;
        ( $m{fs}, $m{dir} ) = m[(^/.*?) .*($dir)$]g;
        ( $m{vg}, $m{lv} ) = split(" ", `lvs $m{fs} --noheadings -o vg_name,lv_name`);
    }
    close $pipe;

    my( @pv, %disk ) = ();
    open my $p,"-|","pvs -o pv_name,lv_name,vg_name";
    while(<$p>){
        my ($pv,$lv,$vg) = split(" ", $_);
        if( $vg eq $m{vg} and $lv eq $m{lv} ){ 
            s/.*?(\/.*\/)(.*)[0-9]+/$1$2/;
            $m{disk}{$2} = $1 . $2;
        }
    }
    close $p;

    return \%m;
};

# create partition on disk with optional size
my $create_part = sub {
    my( $disk, $size ) = @_;
    my $part_extended = "0";

    #run fdisk to create partition, return hasref of created partition
    my $create = sub {
        my( $seq ) = @_;

        my $seen = {};
        for( @{$get_part->($disk)} ){ 
            $part_extended = "1" if $_->{type} eq "Extended";
            $seen->{"$_->{path}"} = $_->{type};
        }
        return if $seq->[1] =~ /e/ and $part_extended eq "1";

        open my $pipe,'|-', "fdisk /dev/$disk";
        for( @$seq ){ print $pipe $_ }; close $pipe;
        system("partprobe /dev/$disk"); # write chages with partprobe
        
        return if $seq->[0] =~ /t/; # return if changing part to LVM
        my( $part ) = grep { ! exists $seen->{"$_->{path}"} } @{$get_part->($disk)};
        if( $part->{type} eq "Extended" ) { $part_extended = "1" }
        $part->{number} = $part->{path}; $part->{number} =~ s/\/.*?([0-9]+)/$1/;

        return $part;
    };

    my $seq = {
        e   =>  ["n\n","e\n","\n","\n","\n","w\n"],
        l   =>  ["n\n","\n","\n","w\n"],
        p   =>  ["n\n","\n","\n","\n","\n","w\n"],
    };

    # create extended partition if doesnt exist
    $create->($seq->{e}) unless $part_extended eq "1";

    #try to create logical partition...
    $seq->{l}->[2] = "$size\n" if defined $size;
    my $p = $create->($seq->{l});

    #...create primary partition if creating logical failed
    unless( $p->{type} eq "Linux" ){
        $seq->{p}->[4] = "$size\n" if defined $size;
        $p = $create->($seq->{p});
    }

    # change partition type to LVM
    $seq->{t} = ["t\n","$p->{number}\n","8e\n","w\n"]; 
    my $t = $create->($seq->{t});
    die $! unless $t->{type} eq "LVM";

    return $t;
};

$create_part->('sde','+1G'); die;

my $lv_exist = sub {
    my( $name, $type ) = @_;
    my $cmd = $type . 's';
    open my $p,'-|', "$cmd --noheadings";

    my $exist = ();
    while(<$p>){ chomp($exist = $_) if $_ =~ /$name/ }
    close $p;
    if($exist){
        $exist =~ s/\s+(.*?)\s+(.*?)\s.*/$1$2/;
        return $2 if $name eq $1;
    }
};

my $lvm = sub {
    my $m = shift;
    mkpath($m->{dir}) unless -d $m->{dir};

    my $create = {
        pv  =>  sub{
                    my $p = "pvcreate $m->{pv}";
                },
        vg  =>  sub{ 
                    my $v = "vgextend $m->{vg} $m->{pv}" if $lv_exist->("$m->{vg}",'vg');
                    $v = "vgcreate $m->{vg} $m->{pv}" unless $lv_exist->("$m->{vg}",'vg');
                    return $v;
                },
        lv  =>  sub{
                    my $lve = $lv_exist->($m->{lv},'lv');
                    if( defined $lve ){ 
                        return "lvextend -l +100%FREE /dev/$m->{vg}/$m->{lv} && resize2fs /dev/$m->{vg}/$m->{lv}";
                    } else {
                        return "lvcreate -n $m->{lv} -l 100%FREE $m->{vg} && mkfs.ext4 /dev/$m->{vg}/$m->{lv}";
                    }
                },
        };
        system($create->{pv}->());
        system($create->{vg}->());
        system($create->{lv}->());
        system("mount /dev/$m->{vg}/$m->{lv} $m->{dir}");
};

=head1
sub expand {
    my ($dir, $size) = @_;
    die "$dir doesnt exist" unless -d $dir;

    my $m = $get_dir->($dir, $size);
    $m->{dir} = $dir;
    $m->{size} = $size if defined size;

    for(keys %{$m->{pv_choose}}){
        s/.*\/(.*)/$1/;
        my $d = $get_part->($_, $size);
        my $p = $create_part->($d, $size);
        #say ">>>> before \$m->{pv} delete:" . Dumper $m;
        delete $m->{pv};
        $m->{pv} = $p->{path},
        say ">>>> after \$m->{pv} delete:" . Dumper $m;
        my $ch = $lvm->($m);
    }
}

expand('/B','+1G');
die;
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
extend existing disk in vm to 7G and reboot OR add new disk in vm and to see changes in host do (for i in `ls -tr  /sys/class/scsi_host/`;do echo "- - -" > /sys/class/scsi_host/$i/scan;done) 


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

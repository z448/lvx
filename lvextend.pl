#!/usr/bin/env perl

use 5.010;
use warnings;
use strict;

use Data::Dumper;
use Data::Dump::Streamer;
use File::Path qw( mkpath );
use Getopt::Std;

use Test::Simple tests => 3;

my $opt = {};
getopts('n:e:', $opt);


# get hashref of exsisting $disk partitions
my $disk = sub {
    my( $disk ) = @_;
    my( @p ) = ();
    my %d = ( name => $disk, path => "/dev/$disk" );

    if(-b $d{path}){
        open my $pipe,'-|',"fdisk -l /dev/$disk";
        while(<$pipe>){ 
            chomp; next unless $_ =~ /^\/dev\//;
            if(/(^\/.*?[0-9]+) .* (.*)$/){ 
                my %p = ();
                $d{extended} = $1 if $2 eq "Extended";
                $p{path} = $1;
                $p{type} = $2;
                push @p, {%p}; 
            }
        }; 
        close $pipe;
        $d{part} = \@p;
    }
    return \%d;
};

my $map = sub {
    my( $dir, $size ) = @_;
    my( %m, @m )= ();

    open my $pipe,"-|","df -h $dir";
    while(<$pipe>){
        next if $_ =~ /Filesystem/;
        ( $m{fs}, $m{dir} ) = m[(^/.*?) .*($dir)$]g;
        ( $m{vg}, $m{lv} ) = split(" ", `lvs $m{fs} --noheadings -o vg_name,lv_name`);

        my( @pv, %pv_choose )= ();
        open my $p,"-|","pvs -o pv_name,lv_name,vg_name";
        while(<$p>){
            my ($pv,$lv,$vg) = split(" ", $_);
            if( $vg eq $m{vg} ){ 
                push @pv, $pv;
                $pv =~ s/(.*?)([0-9]+)/$1$2/;

                if( $lv eq $m{lv} ){
                        chomp( $pv_choose{"$1"} = `lsblk -bdnl $1 --output SIZE` );
                        my $d = $1; $d =~ s[/dev/(.*)][$1];
#                        $m{disk}->{"$1"} = $disk->($d);
                    }
            }
        }
        $m{pv} = \@pv;
        close $p;

        my %pv_size;
        for( @pv ){
            s[(.*)(\d+)$][$1$2]g; 
            if(exists $pv_choose{"$1"}){ 
                $pv_size{"$1"} += `lsblk -bdnl $1 --output SIZE`;
            };
        }
        for( keys %pv_size ){
            say "$_  $pv_size{$_}";
            #unless($pv_choose{$_} == $pv_size{$_}){ delete $pv_choose{$_} }
            unless($pv_choose{$_} == $pv_size{$_}){ next  }
        }

        $m{pv_choose} = \%pv_choose;
    }
    close $pipe;
    return \%m;
};

# create partition on disk with optional size
my $part = sub {
    my( $d, $size ) = @_;

    #run fdisk to create partition, return hasref of created partition
    my $create = sub {
        my( $seq,$d ) = @_;
        my $seen = {};
        for( @{$disk->($d->{name})->{part}} ){ $seen->{"$_->{path}"} = $_->{type} }

        open my $pipe,'|-', "fdisk $d->{path}";
        for( @$seq ){ print $pipe $_ }; close $pipe;
        system("partprobe $d->{path}"); # write chages with partprobe
        
        my $state = $disk->($d->{name})->{part};
        my( $p ) = grep { ! exists $seen->{"$_->{path}"} } @$state;
        $p->{number} = $p->{path}; $p->{number} =~ s/\/.*?([0-9]+)/$1/;

        return $p;
    };

    my $seq = {
        e   =>  ["n\n","e\n","\n","\n","\n","w\n"],
        l   =>  ["n\n","\n","\n","w\n"],
        p   =>  ["n\n","\n","\n","\n","\n","w\n"],
    };

    # create extended partition if doesnt exist
    unless( exists $d->{extended} ){
        my $e = $create->($seq->{e},$d);
        $d->{extended} = $e->{path}; 
        ok( $e->{type} eq "Extended", 'create extended' );
    }

    #try to create logical partition...
    $seq->{l}->[2] = "$size\n" if defined $size;
    my $p = $create->($seq->{l},$d);
    ok( $p->{type} eq 'Linux', 'create logical part');

    #...create primary partition if creating logical failed
    unless($p->{type} eq 'Linux'){
        $p = undef;
        $seq->{p}->[4] = "$size\n" if defined $size;
        $p = $create->($seq->{p},$d);
        ok( $p->{type} eq 'Linux', 'create primary part');
    }

    # change partition type to LVM
    $seq->{t} = ["t\n","$p->{number}\n","8e\n","w\n"]; 
    my $t = $create->($seq->{t},$d);

    return $p;
};

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

sub expand {
    my ($dir, $size) = @_;
    die "$dir doesnt exist" unless -d $dir;

    my $m = $map->($dir, $size);

    for(keys %{$m->{pv_choose}}){
        s/.*\/(.*)/$1/;
        my $d = $disk->($_, $size);
        my $p = $part->($d, $size);
        #say ">>>> before \$m->{pv} delete:" . Dumper $m;
        delete $m->{pv};
        $m->{pv} = $p->{path},
        say ">>>> after \$m->{pv} delete:" . Dumper $m;
        my $ch = $lvm->($m);
    }
}

expand('/B','+1G');
die;

=head1
unless( defined $opt->{n} or defined $opt->{e} ){ 
    die system("perldoc $0");
}

if(defined $opt->{n}){
    my @new = split(',',$opt->{n});
    my $disk = $new[0]; $disk =~ s/[0-9]//g;

    my $lve = $lv_exist->($new[2],'lv');
    if( defined $lve ){ die "[$new[2]] belongs to [$lve]" unless $lve eq $new[1] }
    die "$new[0] doesnt exist" unless -b $disk;
    die "cant create partition om $new[0], disk is assigned to $lv_exist->($new[0],'pv')" if $lv_exist->($new[0],'pv');

    $lv_new->(@new);
    #my $m = $map->('/big');

    say `lsblk`;

} elsif(defined $opt->{e}) {
    my @extend = split(',',$opt->{e});
    die "cant create partition om $extend[0], disk is assigned to $lv_exist->($extend[0],'pv')" if $lv_exist->($extend[0],'pv');

    my $m = $lvm_old->(@extend);
    $lv_extend->($m);

    say Dumper $m;
    say `lsblk`;
}

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

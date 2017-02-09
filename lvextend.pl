#!/usr/bin/env perl

use 5.010;
use warnings;
use strict;

use Data::Dumper;
use File::Path qw( mkpath );
use Getopt::Std;

my $opt = {};
getopts('h', $opt);


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

# take $dir (/dir),return hashref with its $fs,$vg,$lv,%$disk
my $map_dir = sub {
    my $dir = shift;
    my( %m, @m )= ();
 
    open my $pipe,"-|","df -h $dir";
    while(<$pipe>){
        next if $_ =~ /Filesystem/;
        # if /dir is not mounted on LVM fs return 0  
        return unless $_ =~ m[^/dev/mapper];
        ( $m{fs}, $m{dir} ) = m[(^/.*?) .*($dir)$]g;
        ( $m{vg}, $m{lv} ) = split(" ", `lvs $m{fs} --noheadings -o vg_name,lv_name`);

    }
    close $pipe;

    my( @pv, %disk ) = ();
    open my $p,"-|","pvs -o pv_name,lv_name,vg_name";
    while(<$p>){
        my ($pv,$lv,$vg) = split(" ", $_);
        if( $vg eq $m{vg} and $lv eq $m{lv} ){ 
            s/.*?\/.*\/(.*)[0-9]+/$1/;
            $disk{$1} = 1;
        }
    }
    @{$m{disk}} = grep{ /./ } keys %disk;
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
    #die $! unless $->{type} eq "LVM";

    return $p->{path};
};

# take $name of vg,lv or pv and its $type; returns if doesnt exist
# if type is lv and it exist, returns name of vg which it belongs to
my $lv_exist = sub {
    my( $name, $type) = @_;
    my $cmd = $type . 's';
    open my $p,'-|', "$cmd --noheadings";

    my $exist;
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
                    unless( defined $lve ){ 
                        return "lvcreate -n $m->{lv} -l 100%FREE $m->{vg} && mkfs.ext4 /dev/$m->{vg}/$m->{lv}";
                    } else {
                        return "lvextend -l +100%FREE /dev/$m->{vg}/$m->{lv} && resize2fs /dev/$m->{vg}/$m->{lv}" if $lve eq $m->{vg};
                    }
                },
        };
        system($create->{pv}->());
        system($create->{vg}->());
        system($create->{lv}->());
};

# take optional \@disks( disks on which /dir is already mounted by LVM ) that will be checked first and if they dont have required $size run refresh and find all disks on system with required minimum size
my $choose_disk = sub {
    my %unit = ( k => 1, M => 2, G => 3, T => 4, P => 5 );
    
    my $get_disk = sub {
        my( $req_size ) = @_;

        my( %size, @req_disk ) = ();
    
        $req_size =~ s/\+?([0-9]+)(k|M|G|T|P)/$1$2/;
        $req_size = $1 * ( 1024 ** $unit{$2} );

        open my $p,'-|',"lsblk -lbd  --noheadings -o NAME,SIZE,TYPE";
        while(<$p>){ 
            if( /disk/ ){
                my($disk, $size, $type) = split(" ",$_ ) ;
                $size{$disk} = $size;
            }
        }
        close $p;

        for my $disk( keys %size ){
            my @size = ();
            open $p,'-|',"lsblk -lb /dev/$disk --noheadings -o NAME,SIZE";
            while(<$p>){
                if( /$disk[0-9]+\ +([0-9]+)$/ ){ push @size, $1 }
            }
            for( @size ){ $size{$disk} -= $_ }
            push @req_disk, $disk if $size{$disk} >= $req_size;
            close $p;
        }
        return \@req_disk;
    };

    my $disks = $get_disk->( $_[0],$_[1] );
    unless( @$disks ){
        system(qq|for i in `ls -tr  /sys/class/scsi_host/`;do echo "- - -" > /sys/class/scsi_host/\$i/scan;done|);
        say "scanning for new disks...";
        $disks = $get_disk->( $_[0],$_[1] );
        return unless defined $disks->[0];
    }

    return unless @$disks;
    return $disks->[0] if $#{$disks} == 0; #return $disk if there is only one disk 
    print "choose disk: " . join(' ', @$disks) . "\n";
    chomp(my $disk = <STDIN>);
    die "wrong input: $disk" unless my $ok = grep{ $disk eq $_ } @$disks;
    return $disk;
};

sub new {
    my ($dir, $size, $vg, $lv ) = @_;

    my $m = {};
    # find disks, if there is some with enough free space
    my $disk = $choose_disk->( $size );
    die "there is no disk to expand $dir by $size" unless $disk;
    # create partition on disk with optional size (if no size provided, full disk size expand)
    my $p = $create_part->($disk, $size);
    # use created partition with LVM
    $m->{pv} = $p;
    $m->{vg} = $vg;
    $m->{lv} = $lv;
    $m->{dir} = $dir;

    # we're creating new /dir,vg,lv; die if provided lv already exist and belongs to different vg as provided by user
#    die "wrong input: need vg and lv" unless $lv and $vg; #todo offer lv if not provided
    #my $lv_group = $lv_exist->($m->{lv},'lv'); 
    #if( $lv_group ){ if ($m->{vg} ne $lv_group){ die "$lv belongs to $lv_group" }}
    # create or expand 
    my $l = $lvm->($m);
    # mount if creating /dir,vg,lv
    system("mount /dev/$m->{vg}/$m->{lv} $m->{dir}");
    ## todo 267 add mount to fstab otherwise mount below doesnt work
}

sub expand {
    my ($dir, $size) = @_;

    my $m = $map_dir->($dir);
    my $disk = $choose_disk->( $size );
    die "there is no disk to expand $dir by $size" unless $disk;

    my $p = $create_part->($disk, $size);
    $m->{pv} = $p;

    my $l = $lvm->($m);
}

die unless $ARGV[1]; # dies unless /dir 
if( $ARGV[1] ){ die "wrong input:" unless $ARGV[1] =~ /\+([0-9]+)(k|M|G|T|P)/ }

if( $ARGV[2] ){
    new(@ARGV);
} else { expand(@ARGV) }



=head1 NAME

lvx - extend size of LVM filesystem 

=cut

__DATA__
# if removing pv from vg gives error:"Can't remove final physical volume" use bellow commands to remove vg,pv
vgchange -an vg_a
vgremove vg_a
pvremove /dev/sdb5
---


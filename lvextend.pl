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
my $map_dir = sub {
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

# take $name of vg,lv or pv and its $type; returns 0 if doesnt exist
# if type is lv and it exist, returns name of vg which it belongs to
my $lv_exist = sub {
    my( $name, $type ) = @_;
    my $cmd = $type . 's';
    open my $p,'-|', "$cmd --noheadings";

    my $exist = 0;
    while(<$p>){ chomp($exist = $_) if $_ =~ /$name/ }
    close $p;
    if( $exist =~ /\s+(.*?)\s+(.*?)\s.*/ ){
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

# say Dumper $map_dir->('/B','+1G');die;
 
# take optional \@disks( disks on which /dir is already mounted by LVM ) that will be checked first and if they dont have required $size run refresh and find all disks on system with required minimum size
sub choose_disk {
    my( $disks, $size ) = @_

    for( @$disks ){
        $disk{name} = $_; 
        my @free = ();
        open my $p,'-|',"lsblk -l /dev/$_ --noheadings -o NAME,SIZE";
        while(<$p>){
            if( /$_.*\ ([0-9]+)(.)/ ){ push @free, "$1$2" }
        }
        say for @free;
    }
};


choose_disk('sdf');

sub expand {
    my ($dir, $size, $disk, $vg, $lv ) = @_;
    die "$dir doesnt exist" unless -d $dir;

    my $m = $map_dir->($dir, $size);
    $disk = $m->{disk}->[2] unless defined $disk;

    my $p = $create_part->($disk, $size);
    $m->{pv} = $p;

    $m->{vg} = $vg if defined $vg;
    
    $m->{lv} = $lv if defined $lv;
    my $lv_vgroup = $lv_exist->($m->{lv},'lv'); 
    die "$lv belongs to $lv_vgroup" unless $m->{vg} eq $lv_vgroup;

    my $l = $lvm->($m);
}

#expand(@ARGV);

#!/usr/bin/env perl

use 5.010;
use warnings;
use strict;

use Data::Dumper;
use File::Path qw( mkpath );
use Getopt::Std;

my $opt = {};
my $ch;
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

        my( @pv, %pv_choose )= ();
        open my $p,"-|","pvs -o pv_name,lv_name,vg_name";
        while(<$p>){
            my ($pv,$lv,$vg) = split(" ", $_);
            if( $vg eq $m{vg} ){ 
                push @pv, $pv;
                $pv =~ s/(.*?)([0-9]+)/$1$2/;
                $pv_choose{"$1"} = $2 if $lv eq $m{lv} }
            #$pv_choose{"$1"} = $2 if $lv eq $m{lv} }
        }
        
=head1
        
        open my $p,'-|',"pvs -a";
        while( <$p> ){
            if(/(\/.*?) .*?($m{vg})/){ 
                push @pv, $1;
                my $d = $1; $d =~ s/(.*?)([0-9]+)/$1$2/g;
                $pv_choose{$1} = $2;
            }
        }
=cut
        $m{pv} = \@pv; close $p;
        $m{pv_choose} = \%pv_choose;
        for(keys %pv_choose){ $m{disk} = $_ }
        #$m{disk} = $m{pv}->[0]; $m{disk} =~ s/[0-9]+//g;

        open $p,'-|',"lsblk -dnl $m{disk} --output SIZE";
        chomp( $m{disk_size} = <$p> ); close $p;

        open $p,'-|',"lsblk -dnl $m{lv_path} --output SIZE";
        chomp( $m{lv_size} = <$p> ); close $p;

        $m{pv_next} = $m{disk} . ($pv_choose{"$m{disk}"} + 1);
        #$m{pv_next} = $m{disk} . ($#pv + 2);
        $m{pv_last} = $#pv + 1;
        
        #primary# n \n \n \n $size 
         
        #extended# n e \n \n \n #logical# n \n $size t \n 8e w
                    

        #$m{fdisk_seq} = ["n\n","\n","\n","\n","\n","t\n","\n","8e\n","\n","w\n"]; 
        $m{fdisk_seq} = ["n\n","\n","\n","t\n","\n","8e\n","w\n"]; 
        $m{fdisk_seq}->[2] = "$size\n" if defined $size;
        #$m{fdisk_seq} = ["n\n","e\n","\n","\n","\n","n\n","\n","\n","\n","\n","t\n","\n","8e\n","\n","w\n"]; 
        #$m{fdisk_seq} = ["n\n","\n","\n","\n","\n","t\n","\n","8e\n","\n","w\n"]; 
        # $m{fdisk_seq}->[4] = "$size\n" if defined $size;
        open $p,'-|', "fdisk -l $m{disk}";
        while(<$p>){
            chomp;
            $m{part_extended} = 1 if $_ =~ / Extended$/;
            say "###### $m{part_extended}";#test
            $m{check_pv_next} = $1 if $_ =~ /(^\/.*?[0-9]+) /;
            say "###### $m{check_pv_next}";
        }
        close $p;
            
                #s/(^\/.*?[0-9]+).*/$1/;
            #chomp( $m{check_pv_next} = <$p> );

        unshift(@{$m{fdisk_seq}}, "n\n","e\n","\n","\n","\n") unless $m{part_extended};
        #if(defined $size){ 
            #if( $m{part_extended} ){ 
                #$m{fdisk_seq}->[1] = "l\n";
                #} else { 
                #$m{fdisk_seq}->[4] = "$size\n" if defined $size;
                #}
            #}

        #open $p,'-|', "fdisk -l $m{disk} |tail -1 |cut -d' ' -f1";

    }

    print"\$map:"; say Dumper \%m;
    
    return \%m;
    die;
};

my $lv_create = sub {
    my $m = shift;
	system("pvcreate $m->{pv_next}");
	system("vgextend $m->{vg} $m->{pv_next}");
};

my $fdisk = sub {
    my( $disk, $size ) = @_;


};

my $part = sub {
    my( $disk,$size ) = @_;
    my( %p, @p, %seen ) = ();
    my %d = ( id => $disk, path => "/dev/$disk", part => \@p );

    if(-b $d{path}){
        open my $p,'-|',"fdisk -l /dev/$disk";
        while(<$p>){ 
            chomp; next unless $_ =~ /^\/dev\//;
            if(/(^.*?[0-9]+) .* (.*)$/){ 
                $d{extended} = $1 if $2 eq "Extended";
                $seen{$1} = $2;
                push @p, $1; 
            }
        }; 
        close $p;

        #    open $p,'-|',"find /dev/|grep $disk";
        #while(<$p>){ 
        #    chomp; next if $_ eq $d{path};
        #    push @p, $_ unless exists $seen{$_};
        #}
        #close $p;
    }
    return \%d;
};

my $part_create = sub {
    my( $d, $size ) = @_;

    my $fseq = ["n\n","\n","\n","t\n","\n","8e\n","w\n"]; 
    $fseq->[2] = "$size\n" if defined $size;
    unshift(@$fseq, "n\n","e\n","\n","\n","\n") unless $d->{extended};

    open my $p,'|-', "fdisk $d->{path}" ;
    for( @$fseq ){ print $p $_ }
    close $p;
    system("partprobe $d->{path}");

    my %seen; @seen{ @{$d->{part}} } = ();
    my @part = grep { ! exists $seen{$_} } @{$part->($d->{id})->{part}};
    return \@part;
};

my $d = $part->('sdj');
say Dumper $d;
my $p = $part_create->($d);
say Dumper $p;
die;

my $create_part = sub {
	my $m  = shift;
    my $pv_choose;
    if( scalar keys %{$m->{pv_choose}} > 1 ){
        say "choose disk where to create partition: " . join(' ', keys %{$m->{pv_choose}});
        chomp($pv_choose = <>);
        #if($pv_choose =~ /\//){ $pv_choose =~ s/.*\/// }

        open my $p,'-|',"find /dev/|grep $pv_choose";
        while(<$p>){
            chomp($m->{pv_next} = $_) and last;
        }
        close $p;

        $pv_choose = s/(.*?)([0-9]+)/$1$2/;
        say "\$1:$1 \$2:$2";
        $m->{disk} = $1;
        $m->{pv_next} = $2 + 1; $m->{pv_next} = $m->{disk} . $m->{pv_next};
        #$m->{disk} = $m->{pv_choose}; $m->{disk} =~ s/[0-9]+//g;
        #$m->{pv_next} = $pv_choose . (int($m->{pv_choose}->{"$pv_choose"}) + 1);
    }
=head1
	open my $p,'-|', "fdisk -l $m->{disk}";
    while(<$p>){
        $m->{part_extended} = 1 if $_ =~ /Extended$/;
        chomp( $m->{check_pv_next} = $_);
    }
    #open my $p,'-|', "fdisk -l $m->{disk} |tail -1 |cut -d' ' -f1";
    #chomp( $m->{check_pv_next} = <$p> );
    close $p;

=cut
	open my $p,'|-', "fdisk $m->{disk}" ;
    for( @{$m->{fdisk_seq}} ){ my $s = print $p $_; say "status:".$s };
	close $p;
	system("partprobe $m->{disk}");

    #open $p,'-|', "fdisk -l $m->{disk} |tail -1 |cut -d' ' -f1";
    #chomp( $m->{pv_next} = <$p> );
    #close $p;

    #die "fdisk didn't create partition" if $m->{pv_next} eq $m->{check_pv_next};

    $lv_create->($m);
    print Dumper $m;


    #system("pvcreate $m->{pv_next}");
    #system("vgextend $m->{vg} $m->{pv_next}");

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
    say Dumper $m;
    #die "cant create more LVM partitions on $m->{disk}" if $m->{pv_last} == 4; 
    if( $m->{disk_size} eq $m->{lv_size} ){ die "$m->{lv} size same as $m->{disk} size, nothing to do" }
    else { $create_part->($m,$size); sleep 1; say $lv_extend->($m) }
    return $m;
};

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

my $lv_new = sub {
    my($disk, $vg, $lv, $path, $size) = @_;

#open my $psss,'>&',STDOUT;
#open STDOUT,'+>', undef;

        #$pv_choose = s/(.*?)([0-9]+)/$1$2/;
        #say "\$1:$1 \$2:$2";
        #$m->{disk} = $1;
        #$m->{pv_next} = $2 + 1; $m->{pv_next} = $m->{disk} . $m->{pv_next};

    mkpath($path) unless -d $path;

    my $fdisk = sub {
        my $disk = shift; 

        my $fdisk_seq = ["n\n","e\n","\n","\n","\n","n\n","\n","\n","t\n","\n","8e\n","w\n"];
        $fdisk_seq->[7] = "$size\n" if defined $size;

        open my $p,'|-', "fdisk $disk" ;
        for( @{$fdisk_seq} ){ print $p $_ };
        close $p;

        system("partprobe $disk");
    };

    $fdisk->($disk);
    #if( $disk =~ /[0-9]$/ ){ $ch = $fdisk->($disk) } else { die "need partition not disk" }

    #my $disk = shift;
        open my $p,'-|',"find /dev/|grep $disk";
        chomp(my $part = <$p>);
        say "##" . $part;
        close $p;
        system("pvcreate $part");


    #$ch = system("pvcreate $disk") unless $lv_exist->($disk,'pv');

    my $lvm = {
        vg  =>  sub{ 
                    my $v = "vgextend $vg $part" if $lv_exist->($vg,'vg');
                    $v = "vgcreate $vg $part" unless $lv_exist->($vg,'vg');
                    return $v;
                },
        lv  =>  sub{
                    my $lve = $lv_exist->($lv,'lv');
                    if( defined $lve ){ 
                        return "lvextend -l +100%FREE /dev/$vg/$lv && resize2fs /dev/$vg/$lv";
                    } else {
                        return "lvcreate -n $lv -l 100%FREE $vg && mkfs.ext4 /dev/$vg/$lv";
                    }
                },
        };

        system($lvm->{vg}->());
        system($lvm->{lv}->());
        system("mount /dev/$vg/$lv $path");

        #TODO: for expand
        #  487  pvcreate /dev/sdh4
        #    488  lsblk
        #      489  vgextend vg_z6 /dev/sdh4
        #        490  lvextend -l +100%FREE /dev/vg_z6 && resize2fs /dev/vg_z6/lv_nuc6
        #          491  lvextend -l +100%FREE /dev/vg_z6/lv_nuc6 && resize2fs /dev/vg_z6/lv_nuc6
        #
        #
#open STDOUT,'>&',$psss;
};

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

    my $m = $lvm->(@extend);
    $lv_extend->($m);

    say Dumper $m;
    say `lsblk`;
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

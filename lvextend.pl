#!/usr/bin/env perl

use 5.010;
use Data::Dumper;

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

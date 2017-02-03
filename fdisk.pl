use 5.010;
use warnings;
use strict;


my $fswitch = sub {
    my @s = split('',shift);
    open my $psss,'>&',STDOUT;
    open STDOUT,'+>', '/tmp/.lvx';

    open my $p,"|-","fdisk /dev/sdf";
    my $f = say $p "n\n"; close $p;
    open(STDOUT, ">&", $psss);

    open(my $fh,"<",'/tmp/.lvx');
    while(<$fh>){ 
        if(/  $s[0]  /){ $s[0] = 1 }
        if(/  $s[1]  / and $s[0] eq 1 ){ return 1};
    };
};

say for $fswitch->('al');

package Orr::Pass::Emit;

use strict;
use warnings;

use Orr::Tree qw/walk/;

my %ops;

$ops{const} = sub {
    my ($env, $op) = @_;

    my $value = $op->{pad_entry}{value};
    my $name = "new_const_$op->{type}";
    if (my $ctor = $env->{backend}->can($name)) {
        return $env->{backend}->$ctor($$value);
    }
    else {
        my $type = $op->{type} // "<undef>";
        die "unsupported constant type: $type";
    }
};

$ops{lineseq} = sub {
    my ($env, $op) = @_;

    my @list = @{$op->{list}};
    my $last = pop @list;

    foreach my $expr (@list) {
        my $value = walk($env, $expr);
        $env->{fun}->add_eval($value);
    }

    my $value = walk($env, $last);
    return $value;
};

sub process {
    my ($tree, $backend) = @_;

    my $env = {
        ops => \%ops,
        backend => $backend,
        fun => $backend->new_xsub("anon"),
    };

    my $retval = walk($env, $tree->{root});
    $backend->block_return($env->{fun}, $env->{fun}{preamble}, $retval);

    return $env->{fun};
}

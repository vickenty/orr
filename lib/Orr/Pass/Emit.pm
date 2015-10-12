package Orr::Pass::Emit;

use strict;
use warnings;

use Orr::Tree qw/walk/;

my %ops;

$ops{const} = sub {
    my ($env, $op) = @_;

    my $value = $op->{pad_entry}{value};
    my $name = "new_const_$op->{type}";
    if (my $ctor = $env->{fun}->can($name)) {
        return $env->{fun}->$ctor($$value);
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

$ops{sassign} = sub {
    my ($env, $op) = @_;

    my $lvalue = walk($env, $op->{lvalue});
    my $rvalue = walk($env, $op->{rvalue});

    $env->{fun}->add_assignment($lvalue, $rvalue);

    return $lvalue;
};

$ops{padsv} = sub {
    my ($env, $op) = @_;

    my $pe = $op->{pad_entry};
    die "unsupported outer variable: $pe->{name}" if $pe->{outer};

    return $pe->{lvalue} //= $env->{fun}->new_local($pe->{type}, $pe->{name});
};

$ops{aelemfast} = sub {
    my ($env, $op) = @_;
    my $val = $op->{pad_entry}{value};

    die "\@_ is the only global array supported"
        unless $val == \*_;

    my $index = $env->{fun}->new_const_int($op->{index});
    return $env->{fun}->stack_fetch($index->{value});
};

sub process {
    my ($tree, $backend) = @_;

    my $env = {
        ops => \%ops,
        fun => $backend->new_xsub("anon"),
    };

    my $retval = walk($env, $tree->{root});
    $env->{fun}->return($retval);

    return $env->{fun};
}

1;

package Orr::Pass::Type;
use strict;
use warnings;

use B;
use Orr::Tree;

sub walk {
    my ($env, $op, %args) = @_;
    my $type = Orr::Tree::walk($env, $op, %args);
    return $op->{type} = $type;
}

sub assert_type {
    my ($op, $type, @allow) = @_;
    local $" = ", ";
    die "Type: $op->{op}: argument type $type is not one of allowed types (@allow)"
        unless grep { $_ eq $type } @allow;
}

my %ops;

$ops{lineseq} = sub {
    my ($env, $op) = @_;

    my $last;
    $last = walk($env, $_) foreach @{$op->{list}};

    return $last;
};

$ops{const} = sub {
    my ($env, $op) = @_;

    use Devel::Peek;

    my $val = $op->{pad_entry}{value};
    my $obj = B::svref_2object($val);
    my $flags = $obj->FLAGS;

    return "float" if $flags & (B::SVf_IOK | B::SVf_NOK);
    return "string" if $flags & B::SVf_POK;

    die "Type: invalid constant: $$val";
};

$ops{add} =
$ops{subtract} =
$ops{multiply} =
$ops{divide} =
$ops{modulo} =
$ops{lt} =
$ops{le} =
$ops{gt} =
$ops{ge} =
sub {
    my ($env, $op) = @_;
    my @args = map walk($env, $_, type => "float"), @{$op->{args}};
    assert_type($op, $_, qw/float sv/) foreach @args;

    return "float";
};

$ops{abs} =
$ops{negate} =
sub {
    my ($env, $op) = @_;
    assert_type($op, walk($env, $op->{arg}, type => "float"), qw/float sv/);
    return "float";
};

$ops{rv2av} = sub {
    my ($env, $op) = @_;
    assert_type($op, walk($env, $op->{arg}, type => "array"), qw/array sv/);
    return "array";
};

$ops{rv2hv} = sub {
    my ($env, $op) = @_;
    assert_type($op, walk($env, $op->{arg}, type => "hash"), qw/hash sv/);
    return "hash";
};

$ops{cond_expr} = sub {
    my ($env, $op) = @_;

    my $pred = walk($env, $op->{pred}, type => undef);
    my $then = walk($env, $op->{then});
    my $else = walk($env, $op->{else});

    die "Type: incompatible types in cond branches: $then, $else"
        unless $then eq $else;

    return $then;
};

$ops{padsv} = sub {
    my ($env, $op) = @_;
    my $pe = $op->{pad_entry};

    $pe->{type} = $env->{type}
        if ($env->{type} && (!$pe->{type} || $pe->{type} eq "sv"));

    return $pe->{type};
};

$ops{padav} = sub { "array" };
$ops{padhv} = sub { "hash" };
$ops{gv} = sub { "sv" };

$ops{aelem} = sub {
    my ($env, $op) = @_;

    assert_type($op, walk($env, $op->{array}, type => "array"), "array");
    assert_type($op, walk($env, $op->{index}, type => "float"), "float");

    return "sv";
};

$ops{aelemfast_lex} = sub {
    my ($env, $op) = @_;
    return "sv";
};

$ops{helem} = sub {
    my ($env, $op) = @_;

    assert_type($op, walk($env, $op->{hash}, type => "hash"), "hash");
    assert_type($op, walk($env, $op->{key}, type => "string"), "string");

    return "sv";
};

$ops{sassign} = sub {
    my ($env, $op) = @_;

    my $rvalue = walk($env, $op->{rvalue});
    my $lvalue = walk($env, $op->{lvalue}, type => $rvalue);

    die "Type: incompatible in assignment: $lvalue = $rvalue"
        unless $lvalue eq $rvalue;

    return $rvalue;
};

$ops{aassign} = sub {
    my ($env, $op) = @_;

    my $rvalue = walk($env, $op->{rvalue});
    my $lvalue = walk($env, $op->{lvalue}, type => $rvalue);

    die "Ouch: aassign: bad rvalue type $rvalue"
        unless ref $rvalue eq "ARRAY";

    die "Ouch: aassign: bad lvalue type $lvalue"
        unless ref $lvalue eq "ARRAY";

    my ($lp, $rp) = (0, 0);
    while ($lp < @$lvalue) {
        my $lt = $lvalue->[$lp++];
        my $rt = ($rvalue->[$rp] // "") eq "array" ? "sv" : $rvalue->[$rp++];

        die "Type: insufficient elements on rhs of list assignment"
            unless $rt;

        die "Type: incompatible types in list assignment: $lt = $rt"
            unless $lt eq $rt;
    }

    return $rvalue;
};

$ops{list} = sub {
    my ($env, $op) = @_;

    my $env_type = $env->{type};

    die "Ouch: list: bad context type for list: $env_type"
        unless $env_type eq "sv" || ref $env_type eq "ARRAY";

    my @type = ref $env_type ? @$env_type : "array";
    my @real;
    foreach my $expr (@{$op->{list}}) {
        my $type_hint = !@type || $type[0] eq "array" ? "sv" : shift @type;
        push @real, walk($env, $expr, type => $type_hint);
    }

    return \@real;
};

$ops{leaveloop} = sub {
    my ($env, $op) = @_;

    walk($env, $op->{body}, type => "sv");
    return walk($env, $op->{pred}, type => "sv");
};

sub process {
    my ($tree) = @_;

    my $env = {
        ops => \%ops,
        type => "sv",
    };

    return walk($env, $tree->{root});
}

1;

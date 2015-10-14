use strict;
use warnings;

use Test::More;
use Test::Fatal;
use B::ExprTree;
use DDP;

BEGIN {
    use_ok("Orr::Pass::Type");
}

sub types {
    my ($name, $code, $expect, %types) = @_;

    my $tree = B::ExprTree::build($code);
    my $type;

    my $error = exception { $type = Orr::Pass::Type::process($tree) };
    is $error, undef, "$name: types ok";

    # assume names are unique and strip sigils
    my %all_vars = map { substr($_->{name}, 1) => $_->{type} } @{$tree->{vars}};
    my $all_vars = join ", ", keys %all_vars;
    my %sel_vars = map { $_ => $all_vars{$_} } keys %types;

    is_deeply $type, $expect, "$name: expr";
    is_deeply \%sel_vars, \%types, "$name: vars";
}

sub error {
    my ($name, $code) = @_;

    my $tree = B::ExprTree::build($code);
    like exception { Orr::Pass::Type::process($tree) }, qr/^Type/, $name;
}

types "addition",
    sub { my $x + my $y } => "float",
    x => "float",
    y => "float";

types "division",
    sub { my $x / my $y } => "float",
    x => "float",
    y => "float";

types "division by num",
    sub { my $x / 2 } => "float",
    x => "float";

error "division by string",
    sub { my $x / "foo" };

types "cond_expr",
    sub { my (@a, $x, $y); $a[0] ? $x : $y } => "sv",
    x => "sv",
    y => "sv";

types "cond_expr num",
    sub { my @a; $a[0] ? 1 : 2 } => "float";

error "cond_expr conflict",
    sub { my @a; $a[0] ? 1 : "foo" };

types "propagate into cond_expr",
    sub { 2 + (my $x ? my $y : 2) } => "float",
    x => undef,
    y => "float";

types "array subscript",
    sub { my (@a, $y); $a[$y] } => "sv",
    y => "float";

types "arrayref subscript",
    sub { my ($x, $y); $x->[$y] } => "sv",
    x => "array",
    y => "float";

types "hash get",
    sub { my (%h, $y); $h{$y} } => "sv",
    y => "string";

types "hashref get",
    sub { my ($x, $y); $x->{$y} } => "sv",
    x => "hash",
    y => "string";

types "assign num",
    sub { my $x = 1 } => "float",
    x => "float";

types "assign str",
    sub { my $x = "foo" } => "string",
    x => "string";

types "assign expr",
    sub { my $j = my $x + my $y } => "float",
    x => "float",
    y => "float",
    j => "float";

types "assign aelem to float",
    sub { my @a; my $i = $a[0]; $i + 1 } => "float",
    i => "float";

types "assign float to aelem",
    sub { my @a; $a[0] = 1; } => "sv";

types "sv upgrade",
    sub { my %h; my $x = $h{foo}; $x + 1 } => "float",
    x => "float";

error "assign conflict",
    sub { my $x = 1; $x = "foo" };

error "bad use",
    sub { my $x; $x + $x->{foo} };


types "list assign",
    sub { my @a; my ($h, $j, $k, $l) = (1, "foo", @a); },
    [ "float", "string", "array" ],
    h => "float",
    j => "string",
    k => "sv",
    l => "sv";

error "list assign: short rhs",
    sub { my ($h, $j) = (1); };

types "args: list unpack",
    sub { my ($h, $j) = @_; } => [ "array" ],
    h => "sv",
    j => "sv";

types "full: gcd",
    sub {
        my ($u, $v) = @_;
        my $t;
        while ($v) {
            $t = $u;
            $u = $v;
            $v = $t % $v;
        }
        $u < 0 ? -$u : $u;
    },
    "float",
    u => "float",
    v => "float",
    t => "float";

my $global;
types "global scalar",
    sub { $global }, "sv",
    global => "sv";

done_testing;

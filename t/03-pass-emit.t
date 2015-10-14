use strict;
use warnings;

use Test::More;

use DynaLoader;

use B::ExprTree;
use Orr::Pass::Type;
use Orr::Backend::GCCJIT;

use_ok("Orr::Pass::Emit");

sub default_caller {
    my ($code, $args) = @_;
    return $code->(@$args);
}

sub try {
    my ($name, $code, $args, %opts) = @_;

    my $backend = Orr::Backend::GCCJIT->new();
    my $tree = B::ExprTree::build($code);
    Orr::Pass::Type::process($tree);
    Orr::Pass::Emit::process($tree, $backend);

    my $res = $backend->compile();
    my $ptr = $res->get_code("anon");

    my $sub = do {
        no warnings "redefine";
        DynaLoader::dl_install_xsub("anon", $ptr);
    };

    my $caller = $opts{caller} || \&default_caller;

    my @ret = $caller->($sub, $args);
    my @exp = $caller->($code, $args);

    is_deeply \@ret, \@exp, $name;
}

try "const iv", sub { 42 };
try "const nv", sub { -1.5e-1 };
try "sassign", sub { my $x = 42; my $y = $x; $y };
try "multiply", sub { my $x = 6; my $y = 7; $x * $y; };
try "sassign argument", sub { my $x = $_[0]; $x }, [ 42 ];
try "coerce on op", sub { $_[0] * $_[1] }, [ 6, 7 ];
try "coerce on sassign", sub { my $x = $_[0]; my $y = $_[1]; $x * $y }, [ 6, 7 ];

try "sassign to \@_", sub { $_[0] = $_[0] * 2 }, [ 4 ],
    caller => sub {
        my ($code, $args) = @_;
        my @args = @$args;
        my @ret = $code->(@args);
        is $args[0], 8;
        return @ret;
    };

done_testing;

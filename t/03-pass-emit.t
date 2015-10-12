use strict;
use warnings;

use Test::More;

use DynaLoader;

use B::ExprTree;
use Orr::Pass::Type;
use Orr::Backend::GCCJIT;

use_ok("Orr::Pass::Emit");

sub try {
    my ($name, $code, @args) = @_;

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

    my @ret = $sub->(@args);
    my @exp = $code->(@args);

    is_deeply \@ret, \@exp, $name;
}

try "const iv", sub { 42 };
try "const nv", sub { -1.5e-1 };
try "sassign", sub { my $x = 42; my $y = $x; $y };
try "sassign argument", sub { my $x = $_[0]; $x }, 42;

done_testing;

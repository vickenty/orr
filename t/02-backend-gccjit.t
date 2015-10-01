use strict;
use warnings;
use Test::More;

BEGIN {
    require_ok("Orr::Backend::GCCJIT");
}

my $b = Orr::Backend::GCCJIT->new();
can_ok($b, qw/new_xsub compile get_code/);

my $x = $b->new_xsub("test_xsub");
$x->return($b->new_const_float(42));

my $res = $b->compile();
my $ptr = $b->get_code($res, "test_xsub");

DynaLoader::dl_install_xsub("main::test_xsub", $ptr);

is test_xsub(), 42;

done_testing;

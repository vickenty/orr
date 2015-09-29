use strict;
use warnings;

use Test::More;

use DynaLoader;

use B::ExprTree;
use Orr::Pass::Type;
use Orr::Backend::GCCJIT;

use_ok("Orr::Pass::Emit");

my $backend = Orr::Backend::GCCJIT->new();

my $tree = B::ExprTree::build(sub { 42 });
my $type = Orr::Pass::Type::process($tree);
my $code = Orr::Pass::Emit::process($tree, $backend);

my $res = $backend->compile();
my $ptr = $res->get_code("anon");
DynaLoader::dl_install_xsub("test_xsub", $ptr);

is test_xsub(), 42;

done_testing;

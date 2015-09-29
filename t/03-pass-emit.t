use strict;
use warnings;

use Test::More;
use List::Util qw/reduce/;

use B::ExprTree;
use Orr::Pass::Type;
use Orr::Backend::GCCJIT;

use_ok("Orr::Pass::Emit");

my $backend = Orr::Backend::GCCJIT->new();

my $tree = B::ExprTree::build(sub { 42 });
my $type = Orr::Pass::Type::process($tree);
my $code = Orr::Pass::Emit::process($tree, $backend);

print "$type\n";
print "$code\n";

done_testing;

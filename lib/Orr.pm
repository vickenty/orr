package Orr;

use strict;
use warnings;

use B::ExprTree;
use Orr::Pass::Type;
use Orr::Pass::Emit;
use Orr::Backend::GCCJIT;

sub compile {
    my ($code) = @_;

    my $backend = Orr::Backend::GCCJIT->new;
    my $tree = B::ExprTree::build($code);

    Orr::Pass::Type::process($tree);
    Orr::Pass::Emit::process($tree, $backend);

    my $res = $backend->compile();
    my $ptr = $res->get_code("anon");

    my $sub = do {
        no warnings "redefine";
        DynaLoader::dl_install_xsub("Orr::anon_xsub", $ptr);
    };

    return $sub;
}

1;

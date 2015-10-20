package Orr;

use strict;
use warnings;

use B::ExprTree;
use Orr::Pass::Type;
use Orr::Pass::Emit;
use Orr::Backend::GCCJIT;

package Orr::Sub {
    my %stash;

    sub new {
        my ($class, $coderef, $env) = @_;
        my $self = bless $coderef, $class;
        $stash{$self} = $env;
        return $self;
    }

    sub DESTROY {
        my $self = shift;
        delete $stash{$self};
    }
}

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

    return Orr::Sub->new($sub, {
        result => $res,
    });
}

1;

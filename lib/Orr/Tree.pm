package Orr::Tree;

use strict;
use warnings;

use Exporter::Easy OK => [ qw/walk/ ];

sub walk {
    my ($env, $op, %args) = @_;

    my $name = $op->{op};
    my $impl = $env->{ops}{$name} // die "unsupported op '$name'";

    $impl->({ %$env, %args }, $op);
}

1;

use strict;
use warnings;

use Test::More;

require_ok "Orr";

my $test = sub {
    if ($_[0] * 2) {
        $_[1];
    } else {
        $_[2];
    }
};
my $code = Orr::compile($test);

sub try {
    my ($name, @args) = @_;
    my $got = $code->(@args);
    my $exp = $test->(@args);

    is $got, $exp, $name;
}

try "false", 0, 1, 2;
try "true", 1, 2, 3;
try "nan", "nan", 3, 4;
try "inf", "inf", 3, 4;
try "undef", undef, 3, 4;

done_testing;

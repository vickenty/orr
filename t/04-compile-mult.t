use strict;
use warnings;
no warnings "portable";

use Test::More;

require_ok "Orr";

my $test = sub {
    $_[0] * 2;
};
my $code = Orr::compile($test);

sub try {
    my $case = shift;
    my $got = $code->($case);
    my $exp = $test->($case);
    is $got, $exp, "double: $case";
}

my @cases = ( 
    0,
    0.5,
    0.25,
    1,
    0xffff_ffff,
    # Differences in number representation cause tests to fail
    # for any number between the next two.
    499999999999999,
    0x8000000000000000,
    0xffff_ffff_ffff_ffff,
    "nan",
    "inf",
);

foreach my $case (@cases) {
    try $case;
    try -$case;
}

done_testing;

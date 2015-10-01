package Orr::Backend::GCCJIT::Util;

use strict;
use warnings;

use Exporter "import";
our @EXPORT_OK = qw/cast_to/;
our %EXPORT_TAGS = (":all" => \@EXPORT_OK);

sub cast_to {
    my ($dst_type, $arg) = @_;

    return [ map cast_to($dst_type, $_), @$arg ] if ref $arg eq "ARRAY";

    my $class = ref $arg;
    my ($src_type) = $class =~ /^gcc_jit_(\w+)Ptr$/;
    die "unsupported arg type $class" unless $src_type;

    return $arg if $src_type eq $dst_type;

    my $name = "as_${dst_type}";
    my $impl = $arg->can($name) or die "cannot cast $src_type into $dst_type";

    return $impl->($arg);
}

1;

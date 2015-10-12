package Orr::Backend::GCCJIT::Function;

use strict;
use warnings;

use List::Util qw/all/;
use Orr::Backend::GCCJIT::Util qw/cast_to/;

sub create {
    my ($class, $backend, $name) = @_;

    my $perl = $backend->new_param(perl_ptr => "perl");
    my $cv = $backend->new_param(cv => "cv");
    my $fn = $backend->new_function(void => $name, [ $perl, $cv ]);
    my $stack_value = $fn->new_local(undef, $backend->get_jit_type("stack"), "stack");
    my $stack = $stack_value->get_address(undef);
    my $block = $backend->new_block($fn, "top");
    $backend->eval_shim($block, "stack_init", $perl, $stack);

    return bless {
        backend => $backend,
        name => $name,
        perl => $perl,
        cv => $cv,
        fn => $fn,
        stack => $stack,
        block => $block,
    }, $class;
}

my %shim_for_type = ( float => "nv" );
sub auto_push {
    my ($self, $value) = @_;
    my $type = $value->{type};
    $type = $shim_for_type{$type} // $type;

    my $name = "stack_xpush_$type";
    $self->{backend}->eval_shim($self->{block}, $name, @$self{"perl", "stack"}, cast_to("rvalue", $value->{value}));
}

sub return {
    my ($self, @values) = @_;
    my $backend = $self->{backend};
    
    $backend->eval_shim($self->{block}, "stack_prepush", @$self{"perl", "stack"});
    $self->auto_push($_) foreach @values;
    $backend->eval_shim($self->{block}, "stack_putback", @$self{"perl", "stack"});
    $self->{block}->end_with_void_return(undef);
}

sub add_eval {
    my ($self, $value) = @_;
    $self->{block}->add_eval(undef, cast_to("rvalue", $value->{value}));
}

sub new_const_int {
    my ($self, $value) = @_;
    return $self->{backend}->new_const_int($value);
}

sub new_const_float {
    my ($self, $value) = @_;
    return $self->{backend}->new_const_float($value);
}

sub new_local {
    my ($self, $type, $name) = @_;
    $self->{backend}->new_local($self->{fn}, $type, $name);
}

sub add_assignment {
    my ($self, $lval, $rval) = @_;
    $self->{block}->add_assignment(undef, cast_to("lvalue", $lval->{value}), cast_to("rvalue", $rval->{value}));
}

sub stack_fetch {
    my ($self, $index) = @_;
    $self->{backend}->call_shim("stack_fetch", @$self{"perl", "stack"}, cast_to("rvalue", $index))
}

my %op = (
    multiply => GCCJIT::GCC_JIT_BINARY_OP_MULT,
);

sub new_binary_op {
    my ($self, $name, $type, @args) = @_;
    my $code = $op{$name} or die "unsupported operator $name";

    die "bad $name: arguments must be $type"
        unless all { $_->{type} eq $type }, @args;

    return $self->{backend}->new_binary_op($code, $type, @args);
}

1;

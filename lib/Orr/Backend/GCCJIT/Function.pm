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
    my $block = $fn->new_block("top");
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

# Possibly confusing name: Orr "sv" is what "SV*" in XS, so it's not scalar
# constant, but rather scalar pointer constant. They are used to refer to
# scalars that were created elsewhere and are expected to outlive compiled
# code.
sub new_const_sv {
    my ($self, $value_ref) = @_;
    return $self->{backend}->new_const_sv($value_ref);
}

sub new_local {
    my ($self, $type, $name) = @_;
    $self->{backend}->new_local($self->{fn}, $type, $name);
}

sub convert_sv_to_float {
    my ($self, $type, $rval) = @_;
    return $self->{backend}->call_shim("sv_nv", $self->{perl}, cast_to("rvalue", $rval->{value}));
}

sub convert_float_to_bool {
    my ($self, $type, $rval) = @_;
    return $self->{backend}->new_comparison("ne", $rval, $self->{backend}->new_const_float(0));
}

sub coerce {
    my ($self, $type, $value) = @_;

    if (my $conv = $self->can("convert_$value->{type}_to_${type}")) {
        return $self->$conv($type, $value);
    }

    return $value;
}

sub add_assignment {
    my ($self, $lval, $rval) = @_;

    $rval = $self->coerce($lval->{type}, $rval);

    if ($lval->{type} eq "sv" && $rval->{type} eq "float") {
        $self->{backend}->eval_shim($self->{block}, "sv_setnv", $self->{perl}, cast_to("rvalue", $lval->{value}), cast_to("rvalue", $rval->{value}));
    } else {
        die "bad assignment: $lval->{type} = $rval->{type}" unless $lval->{type} eq $rval->{type};
        $self->{block}->add_assignment(undef, cast_to("lvalue", $lval->{value}), cast_to("rvalue", $rval->{value}));
    }
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

    @args = map $self->coerce($type, $_), @args;

    die "bad $name: arguments must be $type"
        unless all { $_->{type} eq $type }, @args;

    return $self->{backend}->new_binary_op($code, $type, @args);
}

sub new_ternary_op {
    my ($self, %args) = @_;

    my $pred_value = $self->coerce("bool", $args{pred}->());

    my $id = ++$self->{ternary_op_count};

    my $then_block = $self->{fn}->new_block("ternary_${id}_then");
    my $else_block = $self->{fn}->new_block("ternary_${id}_else");
    my $next_block = $self->{fn}->new_block("ternary_${id}_tail");

    my $op_value = $self->new_local($args{type}, "ternary_${id}_value");

    $self->{block}->end_with_conditional(undef, cast_to("rvalue", $pred_value->{value}), $then_block, $else_block);

    $self->{block} = $then_block;
    $self->add_assignment($op_value, $args{then}->());
    $then_block->end_with_jump(undef, $next_block);

    $self->{block} = $else_block;
    $self->add_assignment($op_value, $args{else}->());
    $else_block->end_with_jump(undef, $next_block);

    $self->{block} = $next_block;

    return $op_value;
}

1;

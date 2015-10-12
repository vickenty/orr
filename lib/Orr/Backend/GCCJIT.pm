package Orr::Backend::GCCJIT;

use strict;
use warnings;

use GCCJIT qw/:all/;
use GCCJIT::Context;
use Ouroboros qw/:all/;

use Orr::Backend::GCCJIT::Function;
use Orr::Backend::GCCJIT::Util qw/cast_to/;

my %default_typemap = (
    # Types used internally by the backend.
    void => GCC_JIT_TYPE_VOID,
    cv => GCC_JIT_TYPE_VOID_PTR,
    nv => GCC_JIT_TYPE_DOUBLE,

    perl_ptr => GCC_JIT_TYPE_VOID_PTR,
    void_ptr => GCC_JIT_TYPE_VOID_PTR,
    c_int => GCC_JIT_TYPE_INT,

    # Types used by the translator.
    sv => GCC_JIT_TYPE_VOID_PTR,
    float => GCC_JIT_TYPE_DOUBLE,
);

sub new {
    my ($class) = @_;

    return bless {
        ctx => GCCJIT::Context->acquire(),
        typemap => { %default_typemap },
    }, $class;
}

sub build_type_stack {
    my ($self) = @_;

    my $fields = [
        $self->new_field(void_ptr => "sp"),
        $self->new_field(void_ptr => "mark"),
        $self->new_field(c_int => "ax"),
        $self->new_field(c_int => "items"),
    ];

    return $self->new_struct("stack", $fields);
}

sub build_type_stack_ptr {
    my ($self) = @_;
    return $self->get_jit_type("stack")->get_pointer();
}

sub build_type {
    my ($self, $type) = @_;
    if (my $builder = $self->can("build_type_$type")) {
        return $self->$builder();
    }
    my $id = $self->{typemap}{$type} // die "unsupported type $type";
    return $self->{ctx}->get_type($id);
}

sub get_jit_type {
    my ($self, $type) = @_;
    return $self->{types}{$type} //= $self->build_type($type);
}

sub new_param {
    my ($self, $type, $name) = @_;
    return $self->{ctx}->new_param(undef, $self->get_jit_type($type), $name);
}

sub new_field {
    my ($self, $type, $name) = @_;
    return $self->{ctx}->new_field(undef, $self->get_jit_type($type), $name);
}

sub new_struct {
    my ($self, $name, $fields) = @_;
    return $self->{ctx}->new_struct_type(undef, $name, $fields)->as_type();
}

sub new_function {
    my ($self, $return_type, $name, $params, $kind) = @_;
    $kind //= GCC_JIT_FUNCTION_EXPORTED;
    return $self->{ctx}->new_function(undef, $kind, $self->get_jit_type($return_type), $name, $params, 0);
}

sub new_block {
    my ($self, $function, $name) = @_;
    return $function->new_block($name);
}

sub new_value {
    my ($self, $type, $value) = @_;
    return { type => $type, value => $value };
}

sub new_const_int {
    my ($self, $value) = @_;
    return $self->new_value("c_int", $self->{ctx}->new_rvalue_from_int($self->get_jit_type("c_int"), $value));
}

sub new_const_float {
    my ($self, $value) = @_;
    return $self->new_value("float", $self->{ctx}->new_rvalue_from_double($self->get_jit_type("float"), $value));
}

sub new_local {
    my ($self, $fun, $type, $name) = @_;
    return $self->new_value($type, $fun->new_local(undef, $self->get_jit_type($type), $name));
}

my %shim_type = (
    stack_init => [ qw/void perl_ptr stack_ptr/ ],
    stack_prepush => [ qw/void perl_ptr stack_ptr/ ],
    stack_putback => [ qw/void perl_ptr stack_ptr/ ],
    stack_fetch => [ qw/sv perl_ptr stack_ptr c_int/ ],

    stack_xpush_sv => [ qw/void perl_ptr stack_ptr sv/ ],
    stack_xpush_nv => [ qw/void perl_ptr stack_ptr nv/ ],

    sv_nv => [ qw/float perl_ptr sv/ ],
);

sub build_shim {
    my ($self, $name) = @_;
    my $sig = $shim_type{$name} // die "unsupported shim $name";
    my ($return_type, @param) = map $self->get_jit_type($_), @$sig;

    my $fn_type = $self->{ctx}->new_function_ptr_type(undef, $return_type, \@param, 0);
    my $ptr_getter = Ouroboros->can("ouroboros_${name}_ptr") or die "unsupported shim $name";
    my $fn_ptr = $self->{ctx}->new_rvalue_from_ptr($fn_type, $ptr_getter->());
    return $fn_ptr;
}

sub get_shim {
    my ($self, $name) = @_;
    return $self->{shims}{$name} //= $self->build_shim($name);
}

sub call_shim {
    my ($self, $name, @args) = @_;
    my $type = $shim_type{$name}->[0];
    my $value = $self->{ctx}->new_call_through_ptr(undef, $self->get_shim($name), cast_to("rvalue", \@args));
    return $self->new_value($type, $value);
}

sub eval_shim {
    my ($self, $block, $name, @args) = @_;
    $block->add_eval(undef, $self->call_shim($name, @args)->{value});
}

sub block_end {
    my ($self, $block) = @_;
    $block->end_with_void_return(undef);
}

sub new_xsub {
    my ($self, $name) = @_;

    return Orr::Backend::GCCJIT::Function->create($self, $name);
}

sub compile {
    my ($self) = @_;
    $self->{ctx}->compile();
}

sub get_code {
    my ($self, $result, $name) = @_;
    return $result->get_code($name);
}

sub new_binary_op {
    my ($self, $code, $type, @args) = @_;
    my $value = $self->{ctx}->new_binary_op(undef, $code, $self->get_jit_type($type), map cast_to("rvalue", $_->{value}), @args);
    return $self->new_value($type, $value);
}

1;

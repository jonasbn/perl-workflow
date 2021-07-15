package Workflow::Condition::CheckReturn;

use strict;
use warnings;

our $VERSION = '1.55';

use base qw( Workflow::Condition );
use Workflow::Exception qw( condition_error configuration_error );
use English qw( -no_match_vars );

__PACKAGE__->mk_accessors( 'condition', 'operator', 'argument' );

my %supported_ops = (
    eq => '==',
    lt => '<',
    gt => '>',
    le => '<=',
    ge => '>=',
    ne => '!=',
);

sub _init {
    my ( $self, $params ) = @_;

    unless ( defined $params->{condition} ) {
        configuration_error
            "You must specify the name of the nested condition in the parameter 'condition' for ",
            $self->name;
    }
    $self->condition( $params->{condition} );

    unless ( defined $params->{operator} ) {
        configuration_error "You must define the value for 'operator' in ",
            "declaration of condition ", $self->name;
    }
    $self->operator( $params->{operator} );

    unless ( defined $params->{argument} ) {
        configuration_error "You must define the value for 'argument' in ",
            "declaration of condition ", $self->name;
    }
    $self->argument( $params->{argument} );
}

sub evaluate {
    my ( $self, $wf ) = @_;
    my $cond = $self->condition;
    my $op   = $self->operator;
    my $arg  = $self->argument;

    #    warn "DEBUG: evaluating operator '$op'";

    my $numop = $supported_ops{$op};
    if ( not $numop ) {
        configuration_error "Unsupported operator '$op'";
    }

    # Fetch argument from context or eval, if necessary
    my $argval;
    if ( $arg =~ /^[-]?\d+$/ ) {    # numeric
        $argval = $arg;
    } elsif ( $arg =~ /^[a-zA-Z0-9_]+$/ ) {    # alpha-numeric, plus '_'
        $argval = $wf->context->param($arg);
    } else {
        $argval = eval $arg;
    }

    my $condval = $self->evaluate_condition( $wf, $cond );

    if ( eval "\$condval $op \$argval" ) {
        return 1;
    } else {
        condition_error "Condition failed: '$condval' $op '$argval'";
    }

    configuration_error
        "Unknown error in CheckReturn.pm: cond=$cond, op=$op, arg=$arg";
}

1;

__END__

=pod

=head1 NAME

Workflow::Condition::CheckReturn

=head1 VERSION

This documentation describes version 1.55 of this package

=head1 DESCRIPTION

Using nested conditions (See Workflow::Condition::Nested), this evaluates
a given condition and compares the value returned with a given argument.

=head1 SYNOPSIS

In condition.xml:

    <condition name="check_approvals" class="Workflow::Condition::CheckReturn">
        <param name="condition" value="count_approvals" />
        <!-- operator "ge" means: greater than or equal to -->
        <param name="operator"  value="ge" />
        <param name="argument"  value="$context->{approvals_needed}" />
    </condition>

In workflow.xml:

    <state name="CHECK_APPROVALS" autorun="yes">
        <action name="null_1" resulting_state="APPROVED">
            <condition name="check_approvals" />
        </action>
        <action name="null_2" resulting_state="REJECTED">
            <condition name="!check_approvals" />
        </action>
    </state>

=cut

=head1 PARAMETERS

The following parameters may be configured in the C<param> entity of the
condition in the XML configuration:

=head2 condition

The name of the condition to be evaluated.

=head2 argument

The value to compare with the given condition. This can be one of the following:

=over

=item Integer

The integer value is compared with the return value of the condition.

=item String [a-zA-Z0-9_]

The string is interpreted as the name of a workflow context parameter. The current
value of that parmeter is used in the comparison.

=item String

Any other string is evaluated in an C<eval> block. The result should be numeric.

=back

=head2 operator

The name of the comparison operator to use. Supported values are:

    'eq', 'lt', 'gt', 'le', 'ge', 'ne'

The string names are used to simplify the notation in the XML files. The
above strings map to the following numeric operators internally:

    '==', '<', '>', '<=', '>=', !=

=head1 COPYRIGHT

Copyright (c) 2004-2021 Chris Winters. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

Please see the F<LICENSE>

=head1 AUTHORS

Please see L<Workflow>

=cut

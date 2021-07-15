package Workflow::Condition::GreedyOR;

use strict;
use warnings;

our $VERSION = '1.55';

use base qw( Workflow::Condition );
use Workflow::Exception qw( condition_error configuration_error );
use English qw( -no_match_vars );

__PACKAGE__->mk_accessors('conditions');

sub _init {
    my ( $self, $params ) = @_;

    # This is a tricky one. The admin may have configured this by repeating
    # the param name "condition" or by using unique names (e.g.: "condition1",
    # "condition2", etc.). We'll need to string these back together as
    # an array.
    # Yes, I know. The regex doesn't require the suffix to be numeric.
    my @conditions = ();
    foreach my $key ( sort grep {m/^condition/} keys %{$params} ) {
        push @conditions, $self->normalize_array( $params->{$key} );
    }
    $self->conditions( [@conditions] );

}

sub evaluate {
    my ( $self, $wf ) = @_;
    my $conditions = $self->conditions;

    my $result = 0;

    foreach my $cond ( @{$conditions} ) {
        $result += $self->evaluate_condition( $wf, $cond ) ? 1 : 0;
    }

    if ($result) {
        return $result;
    } else {
        condition_error( "All of the conditions returned 'false': ",
            join ', ', @{$conditions} );
    }
}

1;

__END__

=pod

=head1 NAME

Workflow::Condition::GreedyOR

=head1 VERSION

This documentation describes version 1.55 of this package

=head1 DESCRIPTION

Using nested conditions (See Workflow::Condition::Nested), this evaluates
I<all> given conditions, returning the count of successful checks. If
none of the nested conditions are true, an exeption is thrown.

=head1 SYNOPSIS

In condition.xml:

    <condition name="cond1" ... />
    <condition name="cond2" ... />
    <condition name="cond3" ... />

    <condition name="count_approvals" class="Workflow::Condition::GreedyOR">
        <param name="condition" value="cond1" />
        <param name="condition" value="cond2" />
        <param name="condition" value="cond3" />
    </condition>

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

=head2 condition, conditionN

The condition parameter may be specified as either a list of repeating
entries B<or> with a unique integer appended to the I<condition> string:

    <param name="condition" value="first_condition_to_test" />
    <param name="condition" value="second_condition_to_test" />

B<or>

    <param name="condition1" value="first_condition_to_test" />
    <param name="condition2" value="second_condition_to_test" />

=head1 COPYRIGHT

Copyright (c) 2004-2021 Chris Winters. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

Please see the F<LICENSE>

=head1 AUTHORS

Please see L<Workflow>

=cut

package Workflow::Condition;

use warnings;
use strict;
use base qw( Workflow::Base );
use Carp qw(croak);
use English qw( -no_match_vars );
use Log::Log4perl qw( get_logger );
use Workflow::Exception qw( workflow_error );

$Workflow::Condition::CACHE_RESULTS = 1;
$Workflow::Condition::VERSION = '1.55';

my $log;
my @FIELDS = qw( name class );
__PACKAGE__->mk_accessors(@FIELDS);

sub init {
    my ( $self, $params ) = @_;
    $self->name( $params->{name} );
    $self->class( $params->{class} );
    $self->_init($params);
}

sub _init {return}

sub evaluate {
    my ($self) = @_;
    croak "Class ", ref($self), " must implement 'evaluate()'!\n";
}


sub evaluate_condition {
    my ( $class, $wf, $condition_name) = @_;
    $log ||= get_logger();
    $wf->type;

    my $factory = $wf->_factory();
    my $orig_condition = $condition_name;
    my $condition;

    $log->debug("Checking condition $condition_name");

    local $wf->{'_condition_result_cache'} =
        $wf->{'_condition_result_cache'} || {};

    if ( $Workflow::Condition::CACHE_RESULTS
         && exists $wf->{'_condition_result_cache'}->{$orig_condition} ) {

        my $cache_value = $wf->{'_condition_result_cache'}->{$orig_condition};
        # The condition has already been evaluated and the result
        # has been cached
        $log->debug(
            "Condition has been cached: '$orig_condition', cached result: ",
            $cache_value || ''
            );

        return $cache_value;
    } else {

        # we did not evaluate the condition yet, we have to do
        # it now
        $condition = $wf->_factory()
            ->get_condition( $orig_condition, $wf->type );
        $log->debug( "Evaluating condition '$orig_condition'" );
        my $return_value = $condition->evaluate($wf);
        $wf->{'_condition_result_cache'}->{$orig_condition} = $return_value;

        return $return_value;
    }
}



1;

__END__

=pod

=head1 NAME

Workflow::Condition - Evaluate a condition depending on the workflow state and environment

=head1 VERSION

This documentation describes version 1.55 of this package

=head1 SYNOPSIS

 # First declare the condition in a 'workflow_condition.xml'...

 <conditions>
   <condition
      name="IsAdminUser"
      class="MyApp::Condition::IsAdminUser">
         <param name="admin_group_id" value="5" />
         <param name="admin_group_id" value="6" />
   </condition>
 ...

 # Reference the condition in an action of the state/workflow definition...
 <workflow>
   <state>
     ...
     <action name="SomeAdminAction">
       ...
       <condition name="IsAdminUser" />
     </action>
     <action name="AnotherAdminAction">
      ...
      <condition name="IsAdminUser" />
     </action>
     <action name="AUserAction">
      ...
      <condition name="!IsAdminUser" />
     </action>
   </state>
   ...
 </workflow>

 # Then implement the condition

 package MyApp::Condition::IsAdminUser;

 use strict;
 use base qw( Workflow::Condition );
 use Workflow::Exception qw( configuration_error );

 __PACKAGE__->mk_accessors( 'admin_group_id' );

 sub _init {
     my ( $self, $params ) = @_;
     unless ( $params->{admin_group_id} ) {
         configuration_error
             "You must define one or more values for 'admin_group_id' in ",
             "declaration of condition ", $self->name;
     }
     my @admin_ids = $self->_normalize_array( $params->{admin_group_id} );
     $self->admin_group_id( { map { $_ => 1 } @admin_ids } );
 }

 sub evaluate {
     my ( $self, $wf ) = @_;
     my $admin_ids = $self->admin_group_id;
     my $current_user = $wf->context->param( 'current_user' );
     unless ( $current_user ) {
         return ''; # return false
     }
     foreach my $group ( @{ $current_user->get_groups } ) {
         return 1 if ( $admin_ids->{ $group->id } ); # return true
     }
     return ''; # return false
 }

=head1 DESCRIPTION

Conditions are used by the workflow to see whether actions are
available in a particular context. So if user A asks the workflow for
the available actions she might get a different answer than user B
since they determine separate contexts.

B<NOTE>: The condition is enforced by Workflow::State. This means that
the condition name must be visible inside of the state definition. If
you specify the reference to the condition only inside of the full
action specification in a seperate file then nothing will happen. The
reference to the condition must be defined inside of the state/workflow
specification.

=head1 CONFIGURATION

While some conditions apply to all workflows, you may have a case where
a condition has different implementations for different workflow types.
For example, IsAdminUser may look in two different places for two
different workflow types, but you want to use the same condition name
for both.

You can accomplish this by adding a type in the condition configuration.

 <conditions>
 <type>Ticket</type>
   <condition
      name="IsAdminUser"
      class="MyApp::Condition::IsAdminUser">
         <param name="admin_group_id" value="5" />
         <param name="admin_group_id" value="6" />
   </condition>
 ...

The type must match a loaded workflow type, or the condition won't work.
When the workflow looks for a condition, it will look for a typed condition
first. If it doesn't find one, it will look for non-typed conditions.

=head1 SUBCLASSING

=head2 Strategy

The idea behind conditions is that they can be stateless. So when the
L<Workflow::Factory> object reads in the condition configuration it
creates the condition objects and initializes them with whatever
information is passed in.

Then when the condition is evaluated we just call C<evaluate()> on the
condition. Hopefully the operation can be done very quickly since the
condition may be called many, many times during a workflow lifecycle
-- they are typically used to show users what options they have given
the current state of the workflow for things like menu options. So
keep it short!

=head2 Methods

To create your own condition you should implement the following:

=head3 init( \%params )

This is optional, but called when the condition is first
initialized. It may contain information you will want to initialize
your condition with in C<\%params>, which are all the declared
parameters in the condition declaration except for 'class' and 'name'.

You may also do any initialization here -- you can fetch data from the
database and store it in the class or object, whatever you need.

If you do not have sufficient information in C<\%params> you should
throw an exception (preferably 'configuration_error' imported from
L<Workflow::Exception>).

=head3 evaluate( $workflow )

Determine whether your condition fails by returning a false value or
a true value upon success. You can get the application context information
necessary to process your condition from the C<$workflow> object.

B<NOTE> Callers wanting to evaluate a condition, should not call
this method directly, but rather use the C<< $class->evaluate_condition >>
class method described below.

=head3 _init

This is a I<dummy>, please refer to L</init>

=head2 Caching and inverting the result

If in one state, you ask for the same condition again, Workflow uses
the cached result, so that within one list of available actions, you
will get a consistent view. Note that if we would not use caching,
this might not necessary be the case, as something external might
change between the two evaluate() calls.

Caching is also used with an inverted condition, which you can specify
in the definition using C<<condition name="!some_condition">>.
This condition returns the negation of the original one, i.e.
if the original condition fails, this one does not and the other way
round. As caching is used, you can model "yes/no" decisions using this
feature - if you have both C<<condition name="some_condition">> and
C<<condition name="!some_condition">> in your workflow state definition,
exactly one of them will succeed and one will fail - which is particularly
useful if you use "autorun" a lot.

Caching can be disabled by changing C<$Workflow::Condition::CACHE_RESULTS>
to zero (0):

    $Workflow::Condition::CACHE_RESULTS = 0;

All versions before 1.49 used a mechanism that effectively caused global
state. To address the problems that resulted (see GitHub issues #9 and #7),
1.49 switched to a new mechanism with a cache per workflow instance.


=head3 $class->evaluate_condition( $WORKFLOW, $CONDITION_NAME )

Users call this method to evaluate a condition; subclasses call this
method to evaluate a nested condition.

If the condition name starts with an '!', the result of the condition
is negated. Note that a side-effect of this is that the return
value of the condition is ignored. Only the negated boolean-ness
is preserved.

This does implement a trick that is not a convention in the underlying
Workflow library: by default, workflow conditions throw an error when
the condition is false and just return when the condition is true. To
allow for counting the true conditions, we also look at the return
value here. If a condition returns zero or an undefined value, but
did not throw an exception, we consider it to be '1'. Otherwise, we
consider it to be the value returned.



=head1 COPYRIGHT

Copyright (c) 2003-2021 Chris Winters. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

Please see the F<LICENSE>

=head1 AUTHORS

Please see L<Workflow>

=cut

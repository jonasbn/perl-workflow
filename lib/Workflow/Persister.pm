package Workflow::Persister;

use warnings;
use strict;
use base qw( Workflow::Base );
use English qw( -no_match_vars );
use Log::Log4perl qw( get_logger );
use Workflow::Exception qw( persist_error );

use constant DEFAULT_ID_LENGTH => 8;

$Workflow::Persister::VERSION = '1.55';

my @FIELDS = qw( name class
    use_random use_uuid
    workflow_id_generator history_id_generator );
__PACKAGE__->mk_accessors(@FIELDS);

sub init {
    my ( $self, $params ) = @_;
    for (@FIELDS) {
        $self->$_( $params->{$_} ) if ( $params->{$_} );
    }
    unless ( $self->use_random ) {
        $self->use_random('no');
    }
    unless ( $self->use_uuid ) {
        $self->use_uuid('no');
    }
    $self->log->info( "Initializing persister '", $self->name, "'" );
}

########################################
# COMMON GENERATOR ASSIGNMENTS

sub assign_generators {
    my ( $self, $params ) = @_;
    $params ||= {};

    my ( $wf_gen, $history_gen );
    if ( $self->use_uuid eq 'yes' ) {
        $self->log->debug("Assigning UUID generators by request");
        ( $wf_gen, $history_gen ) = $self->init_uuid_generators($params);
    } elsif ( $self->use_random eq 'yes' ) {
        $self->log->debug("Assigning random ID generators by request");
        ( $wf_gen, $history_gen ) = $self->init_random_generators($params);
    }
    if ( $wf_gen and $history_gen ) {
        $self->workflow_id_generator($wf_gen);
        $self->history_id_generator($history_gen);
    }
}

sub init_random_generators {
    my ( $self, $params ) = @_;
    my $length = $params->{id_length} || DEFAULT_ID_LENGTH;
    eval { require Workflow::Persister::RandomId };
    if (my $msg = $EVAL_ERROR) {
        $msg =~ s/\\n/ /g;
        $self->log->error($msg);
    }
    my $generator
        = Workflow::Persister::RandomId->new( { id_length => $length } );
    return ( $generator, $generator );
}

sub init_uuid_generators {
    my ( $self, $params ) = @_;

    eval { require Workflow::Persister::UUID };
    if (my $msg = $EVAL_ERROR) {
        $msg =~ s/\\n/ /g;
        $self->log->error($msg);
    }
    my $generator = Workflow::Persister::UUID->new();
    return ( $generator, $generator );
}

########################################
# INTERFACE METHODS

sub create_workflow {
    my ( $self, $wf ) = @_;
    persist_error "Persister '", ref($self), "' must implement ",
        "'create_workflow()'";
}

sub update_workflow {
    my ( $self, $wf ) = @_;
    persist_error "Persister '", ref($self), "' must implement ",
        "'update_workflow()'";
}

sub fetch_workflow {
    my ( $self, $wf_id ) = @_;
    persist_error "Persister '", ref($self), "' must implement ",
        "'fetch_workflow()'";
}

# This is the only one that isn't required...
sub fetch_extra_workflow_data {
    my ( $self, $wf ) = @_;

    $self->log->info("Called empty 'fetch_extra_workflow_data()' (ok)");
    $self->log->debug(
        "An empty implementation is not an error as you may ",
        "not need this extra functionality. If you do you ",
        "should use a persister for this purpose (e.g., ",
        "Workflow::Persister::DBI::ExtraData) or ",
        "create your own and just implement this method."
    );
    return;
}

sub create_history {
    my ( $self, $wf, @history ) = @_;
    persist_error "Persister '", ref($self), "' must implement ",
        "'create_history()'";
}

sub fetch_history {
    my ( $self, $wf ) = @_;
    persist_error "Persister '", ref($self), "' must implement ",
        "'fetch_history()'";
}

sub get_create_user {
    my ( $self, $wf ) = @_;
    return 'n/a';
}

sub get_create_description {
    my ( $self, $wf ) = @_;
    return 'Create new workflow';
}

sub get_create_action {
    my ( $self, $wf ) = @_;
    return 'Create workflow';
}

# Only required for DBI persisters.
sub commit_transaction {
    return;
}

sub rollback_transaction {
    return;
}

1;

__END__

=pod

=head1 NAME

Workflow::Persister - Base class for workflow persistence

=head1 VERSION

This documentation describes version 1.55 of this package

=head1 SYNOPSIS

 # Associate a workflow with a persister
 <workflow type="Ticket"
           persister="MainDatabase">
 ...

 # Declare a persister
 <persister name="MainDatabase"
            class="Workflow::Persister::DBI"
            driver="MySQL"
            dsn="DBI:mysql:database=workflows"
            user="wf"
            password="mypass"/>

 # Declare a separate persister
 <persister name="FileSystem"
            class="Workflow::Persister::File"
            path="/path/to/my/workflow"/>

=head1 DESCRIPTION

This is the base class for persisting workflows. It does not implement
anything itself but actual implementations should subclass it to
ensure they fulfill the contract.

The job of a persister is to create, update and fetch the workflow
object plus any data associated with the workflow. It also creates and
fetches workflow history records.

=head1 SUBCLASSING

=head2 Methods

=head3 create_workflow( $workflow )

Stub that warns that the method should be overwritten in the derived
Persister. Since this is a SUPER class.

Generate an ID for the workflow, serialize the workflow data (ID and
state) and set the ID in the workflow.

Returns the ID for the workflow.

=head3 update_workflow( $workflow )

Stub that warns that the method should be overwritten in the derived
Persister. Since this is a SUPER class.

Update the workflow state.

Returns nothing.

=head3 fetch_workflow( $workflow_id )

Stub that warns that the method should be overwritten in the derived
Persister. Since this is a SUPER class.

Retrieve the workflow data corresponding to C<$workflow_id>. It not
found return undef, if found return a hashref with at least the keys
C<state> and C<last_update> (a L<DateTime> instance).

=head3 create_history( $workflow, @history )

Stub that warns that the method should be overwritten in the derived
Persister. Since this is a SUPER class.

Serialize all objects in C<@history> for later retrieval.

Returns C<@history>, the list of history objects, with the history
C<id> and C<saved> values set according to the saved results.

=head3 fetch_history( $workflow )

Stub that warns that the method should be overwritten in the derived
Persister. Since this is a SUPER class.

The derived class method should return a list of hashes containing at least
the `id` key. The hashes will be used by the workflow object to instantiate
L<Workflow::History> objects (or a derived class).


=head3 get_create_user( $workflow )

When creating an initial L<Workflow::History> record to insert into the database,
the return value of this method is used for the value of the "user" field.

Override this method to change the value from the default, "n/a".

=head3 get_create_description( $workflow )

When creating an initial L<Workflow::History> record to insert into the database,
the return value of this method is used for the value of the "description" field.

Override this method to change the value from the default, "Create new workflow".


=head3 get_create_action( $workflow )

When creating an initial L<Workflow::History> record to insert into the database,
the return value of this method is used for the value of the "action" field.

Override this method to change the value from the default, "Create workflow".


=head3 assign_generators( \%params )

Assigns proper generators based on intialization, see L</init>

=head3 fetch_extra_workflow_data ( $workflow )

A stub that warns that the method should be overwritten in the derived
Persister. Since this is a SUPER class.

=head3 commit_transaction

Commit the current transaction if the persister supports transactions.
This stub does not have to be overridden. It is not executed if
autocommit is on.

=head3 rollback_transaction

Roll back the current transaction if the persister supports transactions.
This stub does not have to be overridden. It is not executed if
autocommit is on.

=head3 init

Method to initialize persister based on configuration.

=head3 init_random_generators( \%params )

Initializes random id generators, takes the following named parameters:

=over

=item * length, of random id to be generated

=back

Returns two identical random id generator objects in list context.

=head3 init_uuid_generators( \%params )

Initializes UUID generators, takes no parameters

Returns two identical UUID generator objects in list context.

=head1 TODO

=over

=item * refactor init_random_generators, returns two similar objects?

=item * refactor init_uuid_generators, returns two similar objects?

=item * refactor init_uuid_generators, takes no parameters, even though
we shift parameters in?

=back

=head1 SEE ALSO

=over

=item * L<Workflow::Factory>

=item * L<Workflow::History>

=back

=head1 COPYRIGHT

Copyright (c) 2003-2021 Chris Winters. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

Please see the F<LICENSE>

=head1 AUTHORS

Please see L<Workflow>

=cut

package Workflow::Persister::File;

use warnings;
use strict;
use base qw( Workflow::Persister );
use Data::Dumper qw( Dumper );
use File::Spec::Functions qw( catdir catfile );
use Log::Log4perl qw( get_logger );
use Workflow::Exception qw( configuration_error persist_error );
use Workflow::Persister::RandomId;
use File::Slurp qw(slurp);
use English qw( -no_match_vars );

$Workflow::Persister::File::VERSION = '1.55';

my @FIELDS = qw( path );
__PACKAGE__->mk_accessors(@FIELDS);

sub init {
    my ( $self, $params ) = @_;
    $self->SUPER::init($params);
    unless ( $self->use_uuid eq 'yes' || $self->use_random eq 'yes' ) {
        $self->use_random('yes');
    }
    $self->assign_generators($params);
    unless ( $params->{path} ) {
        configuration_error "The file persister must have the 'path' ",
            "specified in the configuration";
    }
    unless ( -d $params->{path} ) {
        configuration_error "The file persister must have a valid directory ",
            "specified in the 'path' key of the configuration ",
            "(given: '$params->{path}')";
    }
    $self->log->info(
        "Using path for workflows and histories '$params->{path}'");
    $self->path( $params->{path} );
}

sub create_workflow {
    my ( $self, $wf ) = @_;
    my $generator = $self->workflow_id_generator;
    my $wf_id     = $generator->pre_fetch_id();
    $wf->id($wf_id);
    $self->log->debug("Generated workflow ID '$wf_id'");
    $self->_serialize_workflow($wf);
    my $full_history_path = $self->_get_history_path($wf);
    mkdir( $full_history_path, 0777 )
        || persist_error "Cannot create history dir '$full_history_path': $!";

    return $wf_id;
}

sub fetch_workflow {
    my ( $self, $wf_id ) = @_;
    my $full_path = $self->_get_workflow_path($wf_id);
    $self->log->debug("Checking to see if workflow exists in '$full_path'");
    unless ( -f $full_path ) {
        $self->log->error("No file at path '$full_path'");
        persist_error "No workflow with ID '$wf_id' is available";
    }
    $self->log->debug("File exists, reconstituting workflow");
    my $wf_info = eval { $self->constitute_object($full_path) };
    if ($EVAL_ERROR) {
        persist_error "Cannot reconstitute data from file for ",
            "workflow '$wf_id': $EVAL_ERROR";
    }
    return $wf_info;
}

sub update_workflow {
    my ( $self, $wf ) = @_;
    $self->_serialize_workflow($wf);
}

sub create_history {
    my ( $self, $wf, @history ) = @_;
    my $generator   = $self->history_id_generator;
    my $history_dir = $self->_get_history_path($wf);
    $self->log->info("Will use directory '$history_dir' for history");
    foreach my $history (@history) {
        if ( $history->is_saved ) {
            $self->log->debug("History object saved, skipping...");
            next;
        }
        $self->log->debug("History object unsaved, continuing...");
        my $history_id = $generator->pre_fetch_id();
        $history->id($history_id);
        my $history_file = catfile( $history_dir, $history_id );
        # Serialize as hash so reconstituting the object returns a hash again
        # we need to return a list of hashes when returning the history list.
        $self->serialize_object( $history_file, { %$history } );
        $self->log->info("Created history object '$history_id' ok");
        $history->set_saved();
    }
}

sub fetch_history {
    my ( $self, $wf ) = @_;
    my $history_dir = $self->_get_history_path($wf);
    $self->log->debug("Trying to read history files from dir '$history_dir'");
    opendir( HISTORY, $history_dir )
        || persist_error "Cannot read history from '$history_dir': $!";
    my @history_files = grep { -f $_ }
        map { catfile( $history_dir, $_ ) } readdir HISTORY;
    closedir HISTORY;
    my @histories = ();

    foreach my $history_file (@history_files) {
        $self->log->debug("Reading history from file '$history_file'");
        my $history = $self->constitute_object($history_file);
        push @histories, $history;
    }
    return @histories;
}

sub _serialize_workflow {
    my ( $self, $wf ) = @_;
    local $Data::Dumper::Indent = 1;
    my $full_path = $self->_get_workflow_path( $wf->id );
    $self->log->debug("Trying to write workflow to '$full_path'");
    my %wf_info = (
        id          => $wf->id,
        state       => $wf->state,
        last_update => $wf->last_update,
        type        => $wf->type,
        context     => $wf->context,

    );
    $self->serialize_object( $full_path, \%wf_info );
    $self->log->debug("Wrote workflow ok");
}

sub serialize_object {
    my ( $self, $path, $object ) = @_;
    $self->log->info( "Trying to save object of type '",
                      ref($object), "' ", "to path '$path'" );
    open( THINGY, '>', $path )
        || persist_error "Cannot write to '$path': $!";
    print THINGY Dumper($object)
        || persist_error "Error writing to '$path': $!";
    close(THINGY) || persist_error "Cannot close '$path': $!";
    $self->log->debug("Wrote object to file ok");
}

sub constitute_object {
    my ( $self, $object_path ) = @_;

    my $content = slurp($object_path);

    no strict;
    my $object = eval $content;
    croak $EVAL_ERROR if ($EVAL_ERROR);
    return $object;

}

sub _get_workflow_path {
    my ( $self, $wf_id ) = @_;
    $self->log->info( "Creating workflow file from '",
                      $self->path, "' ", "and ID '$wf_id'" );
    return catfile( $self->path, $wf_id . '_workflow' );
}

sub _get_history_path {
    my ( $self, $wf ) = @_;
    return catdir( $self->path, $wf->id . '_history' );
}

1;

__END__

=pod

=head1 NAME

Workflow::Persister::File - Persist workflow and history to the filesystem

=head1 VERSION

This documentation describes version 1.55 of this package

=head1 SYNOPSIS

 <persister name="MainPersister"
            class="Workflow::Persister::File"
            path="/home/workflow/storage"/>

=head1 DESCRIPTION

Main persistence class for storing the workflow and workflow history
records to a filesystem for later retrieval. Data are stored in
serialized Perl data structure files.

=head2 METHODS

=head3 constitute_object

This method deserializes an object.

Takes a single parameter of an filesystem path pointing to an object

Returns the re-instantiated object or dies.

=head3 create_history

Serializes history records associated with a workflow object

Takes two parameters: a workflow object and an array of workflow history objects

Returns: provided array of workflow history objects upon success

=head3 create_workflow

Serializes a workflow into the persistance entity configured by our workflow.

Takes a single parameter: a workflow object

Returns a single value, a id for unique identification of out serialized
workflow for possible deserialization.

=head3 fetch_history

Deserializes history records associated with a workflow object

Takes a single parameter: a workflow object

Returns an array of workflow history objects upon success

=head3 fetch_workflow

Deserializes a workflow from the persistance entity configured by our workflow.

Takes a single parameter: the unique id assigned to our workflow upon
serialization (see L</create_workflow>).

Returns a hashref consisting of two keys:

=over

=item * state, the workflows current state

=item * last_update, date indicating last update

=back

=head3 init ( \%params )

Method to initialize the persister object. Sets up the configured generators

Throws a L<Workflow::Exception> if a valid filesystem path is not provided with
the parameters.

=head3 serialize_object

Method that writes a given object to a given path.

Takes two parameters: path (a filesystem path) and an object

Throws L<Workflow::Exception> if unable to serialize the given object to the
given path.

Returns: Nothing

=head3 update_workflow

Updates a serialized workflow in the persistance entity configured by our
workflow.

Takes a single parameter: a workflow object

Returns: Nothing

=head1 TODO

=over

=item * refactor L</constitute_object>, no checks are made on filesystem prior
to deserialization attempt.

=back

=head1 SEE ALSO

=over

=item * L<Workflow::Persister>

=back

=head1 COPYRIGHT

Copyright (c) 2003-2021 Chris Winters. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

Please see the F<LICENSE>

=head1 AUTHORS

Please see L<Workflow>

=cut

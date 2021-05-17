package TestApp::Action::TicketCreateType;

use strict;
use base qw( Workflow::Action );
use File::Spec::Functions qw( catdir );
use Log::Log4perl         qw( get_logger );
use TestApp::Ticket;
use Workflow::Exception   qw( persist_error );
use Workflow::Factory     qw( FACTORY );

$TestApp::Action::TicketCreate::VERSION = '1.06';

sub execute {
    my ( $self, $wf ) = @_;
    my $log = get_logger();
    $log->debug( "Action '", $self->name, "' with class '", ref( $self ), "' executing..." );

    my $context = $wf->context;
    my @fields = qw( type subject description due_date creator );
    foreach my $field ( @fields ) {
        $self->param( $field, $context->param( $field ) );
        $log->debug( "Value for '$field' : ", $self->param( $field ) );
    }

    my $creator = $self->param( 'creator' ) || $context->param( 'current_user' );
    $log->debug( "Assigned creator as '$creator'" );
    my $ticket = TestApp::Ticket->new({
        type        => $self->param( 'type' ),
        status      => $wf->state,
        subject     => $self->param( 'subject' ),
        description => $self->param( 'description' ),
        creator     => $creator,
        due_date    => $self->param( 'due_date' ),
        last_update => $self->param( 'last_update' ),
    });
    $log->debug( "Created ticket object ok" );
    eval { $ticket->create };
    if ( $@ ) {
        $log->error( $@ );
        die $@;
    }
    $log->debug( "Stored ticket object ok" );
    $context->param( ticket => $ticket );
    $log->info( "Ticket created correctly with ID ", $ticket->id );

    my $persister = FACTORY->get_persister( 'TestPersister' );
    if ( $persister->isa( 'Workflow::Persister::DBI' ) ) {
        my $sql = 'INSERT INTO workflow_ticket ( workflow_id, ticket_id ) ' .
                  'VALUES ( ?, ? )';
        $log->debug( "Will run SQL\n$sql" );
        $log->debug( "Will use parameters: ", join( ', ', $wf->id, $ticket->id ) );
        my $dbh = $persister->handle;
        my ( $sth );
        eval {
            $sth = $dbh->prepare( $sql );
            $sth->execute( $wf->id, $ticket->id );
        };
        if ( $@ ) {
            die "Failed to save additional ticket info: $@\n";
        }
    }
    elsif ( $persister->isa( 'Workflow::Persister::File' ) ) {
        my %wf_ticket = (
            workflow_id => $wf->id,
            ticket_id   => $ticket->id,
        );
        my $link_path = catdir( $persister->path,
                                $wf->id . "_workflow_ticket_link" );
        $persister->serialize_object( $link_path, \%wf_ticket );
    }
    $log->info( "Link table record inserted correctly" );

    $wf->add_history(
        Workflow::History->new({
            action      => 'Create ticket',
            description => sprintf( "New ticket created of type '%s' and subject '%s'",
                                    $self->param( 'type' ), $self->param( 'subject' ) ),
            user        => $creator,
        })
    );
    $log->info( "History record added to workflow ok" );
}

1;

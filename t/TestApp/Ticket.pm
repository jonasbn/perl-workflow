package TestApp::Ticket;

use strict;
use base qw( Class::Accessor );
use Data::Dumper          qw( Dumper );
use DateTime::Format::Strptime;
use File::Spec::Functions qw( catfile );
use Log::Log4perl         qw( get_logger );
use Workflow::Factory     qw( FACTORY );
use Workflow::Persister::RandomId;
use vars qw($VERSION);

$VERSION = '0.01';

my @FIELDS = qw( ticket_id type subject description creator
                 status due_date last_update );
__PACKAGE__->mk_accessors( @FIELDS );

my ( $generator );

my $due_parser    = DateTime::Format::Strptime->new( pattern => '%Y-%m-%d' );
my $update_parser = DateTime::Format::Strptime->new( pattern => '%Y-%m-%d %H:%M' );

sub new {
    my ( $class, $params ) = @_;
    my $log = get_logger();
    $log->info( "Instantiating new $class" );
    my $self = bless( {}, $class );
    for ( @FIELDS ) {
        if ( $params->{ $_ } ) {
            $self->$_( $params->{ $_ } );
            $log->debug( "Assigning parameter '$_': $params->{ $_ }" );
        }
    }
    $generator ||= Workflow::Persister::RandomId->new({ id_length => 8 });
    return $self;
}

sub id {
    goto &ticket_id;
}

sub fetch {
    my ( $class, $id ) = @_;
    my $log = get_logger();
    $log->info( "Fetching existing ticket with ID '$id'" );

    my $persister = FACTORY->get_persister( 'TestPersister' );
    if ( $persister->isa( 'Workflow::Persister::DBI' ) ) {
        my $ticket_fields = '"type", "subject", "description", "creator", "status", "due_date", "last_update"';
        my $sql = 'SELECT %s FROM "ticket" WHERE ticket_id = ?';
        $sql = sprintf( $sql, $ticket_fields );
        $log->debug( "Will use SQL\n$sql" );
        $log->debug( "Will use parameters: $id" );

        my $dbh = $persister->handle;
        my ( $sth );
        eval {
            $sth = $dbh->prepare( $sql );
            $sth->execute( $id );
        };
        if ( $@ ) {
            $log->error( "Error fetching ticket: $@" );
            die "Failed to retrieve ticket: $@";
        }
        my $row = $sth->fetchrow_arrayref;
        $log->debug( "Got database row: ", Dumper( $row ) );
        return $class->new({
            ticket_id   => $id,
            type        => $row->[0],
            subject     => $row->[1],
            description => $row->[2],
            creator     => $row->[3],
            status      => $row->[4],
            due_date    => $due_parser->parse_datetime( $row->[5] ),
            last_update => $update_parser->parse_datetime( $row->[6] )
        });
    }
    elsif ( $persister->isa( 'Workflow::Persister::File' ) ) {
        my $ticket_path = catfile( $persister->path, "${id}_ticket" );
        return $persister->constitute_object( $ticket_path );
    }
}

sub create {
    my ( $self ) = @_;
    my $log = get_logger();

    my $id = $generator->pre_fetch_id();
    $log->info( "Creating new ticket with ID '$id'" );
    my $persister = FACTORY->get_persister( 'TestPersister' );
    if ( $persister->isa( 'Workflow::Persister::DBI' ) ) {
        my $due_date    = ( ref $self->due_date )
                            ? $self->due_date->strftime( '%Y-%m-%d' )
                            : $self->due_date;
        my $update_date = ( ref $self->last_update )
                            ? $self->last_update->strftime( '%Y-%m-%d %H:%M' )
                            : DateTime->now->strftime( '%Y-%m-%d %H:%M' );
        my @fields = qw( ticket_id type subject description
                         creator status due_date last_update );
        my @values = ( $id, $self->type, $self->subject, $self->description,
                       $self->creator, $self->status, $due_date, $update_date );
        my $sql = 'INSERT INTO "ticket" ( %s ) VALUES ( %s )';
        $sql = sprintf( $sql, join( ', ', map { qq{"$_"} } @fields ),
                        join( ', ', map { '?' } @values ) );
        $log->debug( "Will use SQL\n$sql" );
        $log->debug( "Will use parameters: ", join( ', ', @values ) );

        my $dbh = $persister->handle;
        my ( $sth );
        eval {
            $sth = $dbh->prepare( $sql );
            $sth->execute( @values );
        };
        if ( $@ ) {
            $log->error( "Error creating ticket: $@" );
            die "Failed to create ticket: $@";
        }
    }
    elsif ( $persister->isa( 'Workflow::Persister::File' ) ) {
        my $ticket_path = catfile( $persister->path, "${id}_ticket" );
        $persister->serialize_object( $ticket_path, $self );
    }
    $log->info( "Ticket '$id' created ok" );
    $self->ticket_id( $id );
    return $self;
}

sub update {
    my ( $self ) = @_;
    my $log = get_logger();

    my $persister = FACTORY->get_persister( 'TestPersister' );
    if ( $persister->isa( 'Workflow::Persister::DBI' ) ) {
        my $sql = 'UPDATE ticket ' .
                  'SET status = ?, due_date = ?, last_update = ? ' .
                  'WHERE ticket_id = ?';
        my @values = ( $self->status,
                       $self->due_date->strftime( '%Y-%m-%d' ),
                       $self->last_update->strftime( '%Y-%m-%d %H:%M' ),
                       $self->id );
        $log->debug( "Will use SQL\n$sql" );
        $log->debug( "Will use parameters: ", join( ', ', @values ) );

        my $dbh = $persister->handle;
        my ( $sth );
        eval {
            $sth = $dbh->prepare( $sql );
            $sth->execute( @values );
        };
        if ( $@ ) {
            die "Failed to update ticket: $@";
        }
    }
    elsif ( $persister->isa( 'Workflow::Persister::File' ) ) {
        my $id = $self->id;
        my $ticket_path = catfile( $persister->path, "${id}_ticket" );
        $persister->serialize_object( $self, $ticket_path );
    }
    return $self;
}

1;

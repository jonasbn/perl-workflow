#!/usr/bin/perl

use strict;
use App::Ticket;
use Cwd               qw( cwd );
use DBI;
use File::Spec::Functions;
use Getopt::Long      qw( GetOptions );
use Log::Log4perl     qw( get_logger );
use Workflow::Factory qw( FACTORY );

$| = 1;

my $LOG_FILE = 'workflow.log';
if ( -f $LOG_FILE ) {
    my $mtime = (stat $LOG_FILE)[9];
    if ( time - $mtime > 600 ) { # 10 minutes
        unlink( $LOG_FILE );
    }
}
Log::Log4perl::init( 'log4perl.conf' );
my $log = get_logger();

$log->info( "Starting: ", scalar( localtime ) );

my ( $OPT_db_init, $OPT_db_type );
GetOptions( 'db'       => \$OPT_db_init,
            'dbtype=s' => \$OPT_db_type );
$OPT_db_type ||= 'sqlite';

if ( $OPT_db_init ) {
    create_tables();
    print "Created database and tables ok\n";
    exit();
}

FACTORY->add_config_from_file( workflow  => 'workflow.xml',
                               action    => 'workflow_action.xml',
                               validator => 'workflow_validator.xml',
                               condition => 'workflow_condition.xml',
                               persister => 'workflow_persister.xml' );
$log->info( "Finished configuring workflow factory" );

my ( $wf, $user, $ticket );

my %responses = (
    help          => [
        'List all commands and a brief description',
        \&list_commands,
    ],
    wf            => [
        "Create/retrieve a workflow; use 'wf Ticket' to create one, 'wf Ticket ID' to fetch",
        \&get_workflow,
    ],
   state         => [
       'Get current state of active workflow',
       \&get_current_state,
   ],
   actions       => [
       'Get current actions of active workflow',
       \&get_current_actions,
   ],
   action_data   => [
       "Display data required for a particular action; 'action_data FOO_ACTION'",
       \&get_action_data,
   ],
   enter_data    => [
       "Interactively enter data required for an action and place it in context; 'enter_data FOO_ACTION'",
       \&prompt_action_data,
   ],
   context       => [
       "Set data into the context; 'context variable value'",
       \&set_context,
   ],
   context_clear => [
       'Clear data out of context',
       \&clear_context,
   ],
   context_show  => [
       'Display data in context',
       \&show_context
   ],
   execute       => [
       'Execute an action; data for the action should be in context',
       \&execute_action,
   ],
   ticket        => [
       'Fetch a ticket and put it into the context',
       \&use_ticket,
   ],
   quit          => [
       'Exit the application',
       sub { exit(0) },
   ],
);

while ( 1 ) {
    my $full_response = get_response( "TicketServer: " );
    my @args = split /\s+/, $full_response;
    my $response = shift @args;
    if ( my $info = $responses{ $response } ) {
        eval { $info->[1]->( @args ) };
        print "Caught error: $@\n" if ( $@ );
    }
    else {
        print "Response '$response' not valid; available options are:\n",
              "   ", join( ', ', sort keys %responses  ), "\n";
    }
}

print "All done!\n";
$log->info( "Stopping: ", scalar( localtime ) );
exit();

sub prompt_action_data {
    my ( $action_name ) = @_;
    _check_wf();

    unless ( $action_name ) {
        die "Command 'action_data' requires 'action_name' specified\n";
    }
    my @action_fields = $wf->get_action_fields( $action_name );
    foreach my $field ( @action_fields ) {
        if ( $wf->context->param( $field->name ) ) {
            print "Field '", $field->name, "' already exists in context, skipping...\n";
            next;
        }
        my @values = $field->get_possible_values;
        my ( $prompt );
        if ( scalar @values ) {
            $prompt = sprintf( "Value for field '%s' (%s)\n   %s\n   Values: %s\n-> ",
                               $field->name, $field->type, $field->description,
                               join( ', ', map { $_->{value} } @values ) );
        }
        else {
            $prompt = sprintf( "Value for field '%s' (%s)\n   %s\n-> ",
                               $field->name, $field->type, $field->description );

            my $value = get_response( $prompt );
            if ( $value ) {
                $wf->context->param( $field->name, $value );
            }
        }
    }
    print "All data entered\n";
}

sub use_ticket {
    my ( $id ) = @_;
    _check_wf();
    unless ( $id ) {
        die "Command 'ticket' requires the ID of the ticket you wish to use\n";
    }
    $ticket = App::Ticket->fetch( $id );
    print "Ticket '$id' fetched wih subject '", $ticket->subject, "'\n";
    $wf->context->param( ticket => $ticket );
}

sub get_action_data {
    my ( $action_name ) = @_;
    _check_wf();
    unless ( $action_name ) {
        die "Command 'action_data' requires 'action_name' specified\n";
    }
    my @action_fields = $wf->get_action_fields( $action_name );
    print "Data for action '$action_name':\n";
    foreach my $field ( @action_fields ) {
        my @values = $field->get_possible_values;
        if ( scalar @values ) {
        printf( "(%s) (%s) %s [%s]: %s\n",
                $field->type, $field->is_required, $field->name,
                join( '|', map { $_->{value} } @values ),
                $field->description );
        }
        else {
            printf( "(%s) (%s) %s: %s\n",
                    $field->type, $field->is_required, $field->name,
                    $field->description );
        }
    }
}

sub set_context {
    my ( $name, @values ) = @_;
    _check_wf();
    if ( $name and scalar @values ) {
        $wf->context->param( $name, join( ' ', @values ) );
        print "Context parameter '$name' set to '", $wf->context->param( $name ), "'\n";
    }
    else {
        print "Nothing modified in context, no name or value given.\n";
    }
}

sub clear_context {
    _check_wf();
    $wf->context->clear_params;
    print "Context cleared\n";
}

sub list_commands {
    print "Available commands:\n\n";
    foreach my $cmd ( sort keys %responses ) {
        printf( "%s\n  %s\n",
                "$cmd:",
                $responses{ $cmd }->[0] );
    }
    print "\n";
}

sub get_current_state {
    _check_wf();
    print "Current state of workflow is '", $wf->state, "'\n";
}

sub get_current_actions {
    _check_wf();
    print "Actions available in state '", $wf->state, "': ",
          join( ', ', $wf->get_current_actions ), "\n";
}

sub show_context {
    _check_wf();
    my $params = $wf->context->param;
    print "Contents of current context: \n";
    while ( my ( $k, $v ) = each %{ $params } ) {
        if ( ref( $v ) ) {
            $v = 'isa ' . ref( $v );
        }
        print "$k: $v\n";
    }
}

sub execute_action {
    _check_wf();
    my ( $action_name ) = @_;
    unless ( $action_name ) {
        die "Command 'execute_action' requires you to set 'action_name'\n";
    }
    $wf->execute_action( $action_name );
}

sub get_workflow {
    my ( $type, $id ) = @_;
    if ( $id ) {
        print "Fetching existing workflow of type '$type' and ID '$id'...\n";
        $wf = FACTORY->fetch_workflow( $type, $id );
    }
    else {
        print "Creating new workflow of type '$type'...\n";
        $wf = FACTORY->create_workflow( $type );
    }
    print "Workflow of type '", $wf->type, "' available with ID '", $wf->id, "'\n";
}

sub _check_wf {
    unless ( $wf ) {
        die "First create or fetch a workflow!\n";
    }
}


########################################
# DB INIT

sub create_tables {
    my $log = get_logger();
    my ( $dbh, @tables ) = initialize_db();
    for ( @tables ) {
        next if ( /^\s*$/ );
        $log->debug( "Creating table:\n$_" );
        eval { $dbh->do( $_ ) };
        if ( $@ ) {
            die "Failed to create table\n$_\n$@\n";
        }
    }
    $log->info( 'Created tables ok' );
}

my $DB_FILE = 'ticket.db';

sub initialize_db {
    my $log = get_logger();

    my $path = catdir( cwd(), 'db' );
    unless( -d $path ) {
        mkdir( $path, 0777 ) || die "Cannot create directory '$path': $!";
        $log->info( "Created db directory '$path' ok" );
    }

    my ( $dbh );
    my @tables = ();
    if ( $OPT_db_type eq 'sqlite' ) {
        if ( -f $DB_FILE ) {
            $log->info( "Removing old database file..." );
            unlink( $DB_FILE );
        }
        $dbh = DBI->connect( "DBI:SQLite:dbname=db/$DB_FILE", '', '' )
                    || die "Cannot create database: $DBI::errstr\n";
        $dbh->{RaiseError} = 1;
        $log->info( "Connected to database ok" );
        @tables = ( read_tables( '../../struct/workflow_sqlite.sql' ),
                    read_tables( 'ticket.sql' ) );
    }
    elsif ( $OPT_db_type eq 'csv' ) {
        my @names = qw( workflow workflow_history ticket workflow_ticket );
        for ( @names ) {
            if ( -f $_ ) {
                $log->info( "Removing old database file '$_'..." );
                unlink( $_ );
            }
        }
        $dbh = DBI->connect( "DBI:CSV:f_dir=db", '', '' )
                    || die "Cannot create database: $DBI::errstr\n";
        $dbh->{RaiseError} = 1;
        $log->info( "Connected to database ok" );
        @tables = ( read_tables( '../../struct/workflow_csv.sql' ),
                    read_tables( 'ticket_csv.sql' ) );
    }
    return ( $dbh, @tables );
}

########################################
# I/O

sub read_tables {
    my ( $file ) = @_;
    my $table_file = read_file( $file );
    return split( ';', $table_file );
}

sub read_file {
    my ( $file ) = @_;
    local $/ = undef;
    open( IN, '<', $file ) || die "Cannot read '$file': $!";
    my $content = <IN>;
    close( IN );
    return $content;
}

# Generic routine to read a response from the command-line (defaults,
# etc.) Note that return value has whitespace at the end/beginning of
# the routine trimmed.

sub get_response {
    my ( $msg ) = @_;
    print $msg;
    my $response = <STDIN>;
    chomp $response;
    $response =~ s/^\s+//;
    $response =~ s/\s+$//;
    return $response;
}
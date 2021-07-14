package TestApp::Condition::AlwaysTrue;

use strict;
use base qw( Workflow::Condition );
use Log::Log4perl       qw( get_logger );

$TestApp::Condition::AlwaysTrue::VERSION = '0.01';

sub evaluate {
    my ( $self, $wf ) = @_;
    my $log = get_logger();
    $log->debug( "Trying to execute condition ", ref( $self ) );
    $log->debug( 'Condition met ok' );
    return 1;
}

1;

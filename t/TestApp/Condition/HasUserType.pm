package TestApp::Condition::HasUserType;



use strict;
use base qw( Workflow::Condition );
use Log::Log4perl       qw( get_logger );

$TestApp::Condition::HasUserType::VERSION = '0.01';

sub evaluate {
    my ( $self, $wf ) = @_;
    my $log = get_logger();
    $log->debug( "Trying to execute condition ", ref( $self ) );
    unless ( $wf->context->param( 'current_user' ) ) {
        return 0;
    }
    $log->debug( 'Condition met ok' );
    return 1;
}

1;

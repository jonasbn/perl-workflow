package Workflow::Persister::DBI::SequenceId;

use warnings;
use strict;
use base qw( Class::Accessor );
use DBI;
use Log::Log4perl qw( get_logger );
use Workflow::Exception qw( persist_error );
use English qw( -no_match_vars );

$Workflow::Persister::DBI::SequenceId::VERSION = '1.51';

my @FIELDS = qw( sequence_name sequence_select );
__PACKAGE__->mk_accessors(@FIELDS);


sub pre_fetch_id {
    my ( $self, $dbh ) = @_;
    my $full_select = sprintf $self->sequence_select, $self->sequence_name;
    $self->log->is_debug
        && $self->log->debug("SQL to fetch sequence: $full_select");
    my ($row);
    eval {
        my $sth = $dbh->prepare($full_select);
        $sth->execute;
        $row = $sth->fetchrow_arrayref;
        $sth->finish;
    };
    if ($EVAL_ERROR) {
        persist_error "Failed to retrieve sequence: $EVAL_ERROR";
    }
    return $row->[0];
}

sub post_fetch_id {return}

1;

__END__

=pod

=head1 NAME

Workflow::Persister::DBI::SequenceId - Persister to fetch ID from a sequence

=head1 VERSION

This documentation describes version 1.51 of this package

=head1 SYNOPSIS

 <persister
     name="MyPersister"
     workflow_sequence="wf_seq"
     history_sequence="wf_history_seq"
 ...

=head1 DESCRIPTION

Implementation for DBI persister to fetch an ID value from a sequence.

=head2 METHODS

=head3 pre_fetch_id

Returns a unique sequence id from a database.

Takes a single parameter, a L<DBI> database handle.

Returns a single value, a integer representing a sequence id from the provided
database handle.

=head3 post_fetch_id

This is a I<dummy> method, use L</pre_fetch_id>

=head1 COPYRIGHT

Copyright (c) 2003-2021 Chris Winters. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

Please see the F<LICENSE>

=head1 AUTHORS

Please see L<Workflow>

=cut

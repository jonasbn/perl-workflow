#!/usr/bin/env perl

use warnings;
use strict;
use lib qw(../lib lib ../t t);
use Test::More;
use Test::Exception;
use English qw(-no_match_vars);

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($OFF);

use_ok( 'Workflow::Exception', qw(workflow_error validation_error configuration_error persist_error) );

{
    throws_ok {
        workflow_error('test ', 'workflow_error')
    } 'Workflow::Exception', 'workflow workflow_error exception';
    like($EVAL_ERROR, qr/test workflow_error/, 'asserting exception text');
}

{
    throws_ok {
        Workflow::Exception->throw(
            message => 'workflow exception',
            foo     => 'bar',
        );
    } qr/messageworkflow exceptionfoobar/, 'exception thrown';
}

{
    throws_ok {
        validation_error('test ', 'validation_error', { foo => 'bar' })
    } 'Exception::Class::Base', 'workflow validation_error exception';
    like($EVAL_ERROR, qr/unknown field foo passed to constructor for class Workflow::Exception::Validation/, 'asserting exception text');
}

{
    throws_ok {
        configuration_error('test ', 'configuration_error')
    } 'Workflow::Exception', 'workflow configuration_error exception';
    like($EVAL_ERROR, qr/test configuration_error/, 'asserting exception text');
}

{
    throws_ok {
        persist_error('test ', 'persist_error')
    } 'Workflow::Exception', 'workflow persist_error exception';
    like($EVAL_ERROR, qr/test persist_error/, 'asserting exception text');
}
done_testing();

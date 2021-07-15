#!/usr/bin/env perl

use strict;
use lib qw(../lib lib ../t t);
use TestUtil;
use Test::Exception;
use Test::More  tests => 16;

require_ok( 'Workflow::InputField' );

my $action;

dies_ok { $action = Workflow::InputField->new({}) };

ok($action = Workflow::InputField->new({
    name        => 'test',
    is_required => 'yes',
}));

isa_ok($action, 'Workflow::InputField');

my @values;

@values = $action->get_possible_values();

is(scalar @values, 0);

ok(@values = $action->add_possible_values(
    { label => 'foo', value => '1' },
    { label => 'bar', value => '2' },
));

ok(@values = $action->get_possible_values());

is(scalar @values, 2);

is($action->is_required, 'yes');

is($action->is_optional, 'no');

ok($action = Workflow::InputField->new({
    name        => 'test',
    is_required => 'no',
}));

is($action->is_required, 'no');

is($action->is_optional, 'yes');

ok($action = Workflow::InputField->new({
    name        => 'test',
}));

is($action->is_required, 'no');

is($action->is_optional, 'yes');

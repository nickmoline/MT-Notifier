# ===========================================================================
# A Movable Type plugin with subscription options for your installation
# Copyright 2003-2010 Everitz Consulting <everitz.com>.
#
# This program is distributed in the hope that it will be useful but does
# NOT INCLUDE ANY WARRANTY; Without even the implied warranty of FITNESS
# FOR A PARTICULAR PURPOSE.
#
# This program may not be redistributed without permission.
# ===========================================================================
package Notifier::Data;

use strict;

use MT::Object;
@Notifier::Data::ISA = qw(MT::Object);
__PACKAGE__->install_properties({
    column_defs => {
        'id' => 'integer not null auto_increment',
        'blog_id' => 'integer not null',
        'category_id' => 'integer not null',
        'entry_id' => 'integer not null',
        'email' => 'string(75) not null',
        'cipher' => 'string(75) not null',
        'record' => 'smallint not null',
        'status' => 'smallint not null',
        'type' => 'smallint not null',
        'ip' => 'string(40) not null',
    },
    defaults => {
        blog_id => 0,
        category_id => 0,
        entry_id => 0,
        record => 0,
        status => 0,
        type => 0,
    },
    indexes => {
        blog_id => 1,
        category_id => 1,
        entry_id => 1,
        email => 1,
        cipher => 1,
        record => 1,
        status => 1,
        type => 1,
        ip => 1,
    },
    audit => 1,
    class_type => 'subscription',
    datasource => 'notifier_data',
    meta => 1,
    primary_key => 'id',
});

# record status
use constant PENDING => 0;
use constant RUNNING => 1;

# record type
use constant OPT_OUT   => 0;
use constant SUBSCRIBE => 1;
use constant TEMPORARY => 2;

# other
use constant BULK => 1;

sub class_label {
    my $plugin = MT->component('Notifier');
    $plugin->translate('Subscription');
}

sub class_label_plural {
    my $plugin = MT->component('Notifier');
    $plugin->translate('Subscriptions');
}

sub save {
    my $sub = shift;
    if (ref $sub) {
        my @ts = gmtime(time);
        my $ts = sprintf '%04d%02d%02d%02d%02d%02d',
                 $ts[5]+1900, $ts[4]+1, @ts[3,2,1,0];
        $sub->modified_on($ts);
    }
    $sub->SUPER::save(@_);
}

1;

# ===========================================================================
# MT-Notifier: Configure subscriptions to your blog.
# A Plugin for Movable Type
#
# Release 2.2.4
# September 6, 2004
#
# http://jayseae.cxliv.org/notifier/
# http://www.amazon.com/o/registry/2Y29QET3Y472A/
#
# Copyright 2003-2004, Chad Everett (software@cxliv.org)
# ~Licensed under the Open Software License version 2.1~
#
# If you find the software useful or even like it, then a simple 'thank you'
# is always appreciated.  A reference back to me is even nicer.  If you find
# a way to make money from the software, do what you feel is right.
# ===========================================================================
package MT::Plugin::Notifier;

use strict;

use MT;
use MT::Plugin;

use vars qw($VERSION);
$VERSION = '2.2.4';

my $about = {
  name => 'MT-Notifier',
  config_link => '../mt-notifier.cgi?__mode=mnu',
  description => 'Subscription options for your installation.',
  doc_link => 'http://jayseae.cxliv.org/notifier/'
}; 

MT->add_plugin(new MT::Plugin($about));

MT::Comment->add_callback('pre_save', 11, $about, \&Notify);

sub Notify {
  my ($err, $obj) = @_;
  my $notify = $obj->visible;
  if ($obj->id) {
    $notify = 0;
    require MT::Comment;
    if (my $comment = MT::Comment->load($obj->id)) {
      $notify = 1 if ($obj->visible && !$comment->visible);
    }
  }
  if ($notify) {
    require MT::Blog;
    my $blog = MT::Blog->load($obj->blog_id);
    if ($blog->email_new_comments) {
      require jayseae::notifier;
      jayseae::notifier->notify($err, $obj);
    }
  }
}

1;
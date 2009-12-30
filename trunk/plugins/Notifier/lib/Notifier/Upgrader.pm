# ===========================================================================
# A Movable Type plugin with subscription options for your installation
# Copyright 2003-2008 Everitz Consulting <everitz.com>.
#
# This program may not be redistributed without permission.
# ===========================================================================
package Notifier::Upgrader;

use strict;

use Notifier;

sub _set_blog_id {
  require Notifier::Data;
  my $iter = Notifier::Data->load_iter();
  while (my $obj = $iter->()) {
    next if ($obj->blog_id);
    if (my $entry_id = $obj->entry_id()) {
      require MT::Entry;
      if (my $entry = MT::Entry->load($entry_id)) {
        $obj->blog_id($entry->blog_id);
      }
    }
    if (my $category_id = $obj->category_id()) {
      require MT::Category;
      if (my $category = MT::Category->load($category_id)) {
        $obj->blog_id($category->blog_id);
      }
    }
    $obj->cipher(Notifier::produce_cipher(
      'a'.$obj->email.'b'.$obj->blog_id.'c'.$obj->category_id.'d'.$obj->entry_id
    ));
    $obj->save;
  }
}

sub _set_history {
  my $set;
  require MT::Entry;
  my $iter = MT::Entry->load_iter();
  while (my $entry = $iter->()) {
    my $pinged = $entry->pinged_urls;
    $set = 0;
    $set = 1 if ($pinged && $pinged =~ m/$Notifier::SENTSRV1/);
    $set = 1 if ($pinged && $pinged =~ m/$Notifier::SENTSRV2/);
    $set = 1 if ($pinged && $pinged =~ m/$Notifier::SENTSRV3/);
    return unless ($set);
    require Notifier::Data;
    my $blog_id = $entry->blog_id;
    my $entry_id = $entry->id;
    my @subs =
      map { $_ }
      Notifier::Data->load({
        blog_id => $blog_id,
        record => Notifier::SUBSCRIBE,
        status => Notifier::RUNNING
      });
    require MT::Placement;
    my @places = MT::Placement->load({
      entry_id => $entry_id
    });
    foreach my $place (@places) {
      my @category_subs = Notifier::Data->load({
        category_id => $place->category_id,
        record => Notifier::SUBSCRIBE,
        status => Notifier::RUNNING
      });
      foreach (@category_subs) {
        push @subs, $_;
      }
    }
    my $users = scalar @subs;
    next unless ($users);
    require Notifier::History;
    foreach my $sub (@subs) {
      my $data = Notifier::Data->load({
        email => $sub->email,
        record => Notifier::SUBSCRIBE
      });
      next unless ($data);
      next if ($data->entry_id);
      my $history = Notifier::History->load({
        data_id => $data->id,
        entry_id => $entry_id
      });
      next if ($history);
      $history = Notifier::History->new;
      $history->data_id($data->id);
      $history->comment_id(0);
      $history->entry_id($entry_id);
      $history->save;
    }
  }
}

sub _set_ip {
  require Notifier::Data;
  my $iter = Notifier::Data->load_iter();
  while (my $obj = $iter->()) {
    next if ($obj->ip);
    $obj->ip('0.0.0.0');
    $obj->save;
  }
}

1;

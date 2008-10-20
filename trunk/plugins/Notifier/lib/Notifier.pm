# ===========================================================================
# Copyright 2003-2005, Everitz Consulting (mt@everitz.com)
#
# Licensed under the Open Software License version 2.1
# ===========================================================================
package Notifier;

use base qw(MT::App::CMS);
use strict;

use MT;
use Notifier::Data;

# record status
use constant PENDING => 0;
use constant RUNNING => 1;

# record type
use constant OPT     => 0;
use constant SUB     => 1;
use constant TEMP    => 2;

# other
use constant BULK    => 1;

# version
use vars qw($VERSION);
$VERSION = '3.0.0';

sub init {
  my $app = shift;
  $app->SUPER::init (@_) or return;
  $app->add_methods (
    default => \&notifier_request,
    import => \&notifier_import,
    loader => \&notifier_loader,
  );
  $app->{default_mode} = 'default';
  my $mode = $app->{query}->param('__mode');
  $app->{requires_login} = (!$mode) ? 0 : 1;
  $app;
}

sub notifier_import {
  my $notifier = MT::Plugin::Notifier->instance;
  my $app = shift;
  my $auth = ($app->user->is_superuser) ? 1 : 0;
  my $from = $app->{query}->param('from');
  my $d = $app->{query}->param('d');
  my $count = 0;
  my $message;
  if ($auth) {
    if ($from eq 'mt') { 
      use MT::Notification;
      foreach my $data (MT::Notification->load()) {
        next unless ($data && $data->blog_id && $data->email);
        create_subscription($data->email, SUB, $data->blog_id, 0, 0, BULK);
        $count++;
      }
    } elsif ($from eq 'n1x') {
      use MT::PluginData;
      foreach my $data (MT::PluginData->load({ plugin => 'Notifier' })) {
        if ($data->key =~ /^([0-9]+):0$/) {
          my $blog_id = $1;
          my $scope = 'blog:'.$blog_id if ($blog_id);
          if (my $from = $data->data->{'senderaddress'}) {
            $notifier->set_config_value('system_address_type', 1, $scope);
            $notifier->set_config_value('system_address', $from, $scope);
          }
          next unless ($blog_id);
          if (my $subs = $data->data->{'subscriptions'}) {
            foreach my $sub (split(';', $subs)) {
              my ($email) = split(':', $sub);
              create_subscription($email, OPT, $blog_id, 0, 0, BULK);
              $count++;
            }
          }
        } elsif ($data->key =~ /^([1-9][0-9]*):([1-9][0-9]*)$/) {
          my $entry_id = $2;
          if (my $subs = $data->data->{'subscriptions'}) {
            foreach my $sub (split(';', $subs)) {
              my ($email) = split(':', $sub);
              create_subscription($email, SUB, 0, 0, $entry_id, BULK);
              $count++;
            }
          }
        }
      }
    } elsif ($from eq 'n2x') {
      use MT::PluginData;
      foreach my $data (MT::PluginData->load({ plugin => 'Notifier (n2x)' })) {
        next unless ($data->key =~ /:/);
        if ($data->key =~ /^([0-9]+):0$/) {
          my $blog_id = $1;
          my $scope = 'blog:'.$blog_id if ($blog_id);
          if (my $from = $data->data->{'from'}) {
            $notifier->set_config_value('system_address_type', 1, $scope);
            $notifier->set_config_value('system_address', $from, $scope);
          }
          next unless ($blog_id);
          if (my $subs = $data->data->{'subs'}) {
            foreach my $sub (split(';', $subs)) {
              my ($email, $type) = split(':', $sub);
              $type = ($type eq 'opt') ? OPT : SUB;
              create_subscription($email, $type, $blog_id, 0, 0, BULK);
              $count++;
            }
          }
        } elsif ($data->key =~ /^([1-9][0-9]*):C$/) {
          my $category_id = $1;
          if (my $subs = $data->data->{'subs'}) {
            foreach my $sub (split(';', $subs)) {
              my ($email, $type) = split(':', $sub);
              $type = ($type eq 'opt') ? OPT : SUB;
              create_subscription($email, $type, 0, $category_id, 0, BULK);
              $count++;
            }
          }
        } elsif ($data->key =~ /^0:([1-9][0-9]*)$/) {
          my $entry_id = $1;
          if (my $subs = $data->data->{'subs'}) {
            foreach my $sub (split(';', $subs)) {
              my ($email, $type) = split(':', $sub);
              next if ($type eq 'opt');
              create_subscription($email, SUB, 0, 0, $entry_id, BULK);
              $count++;
            }
          }
        }
      }
    }
    my $s = ($count eq 1) ? '' : 's';
    $message = $app->translate("You have successfully converted [_1] record$s!", $count);
  } else {
    $message = $app->translate('You are not authorized to run this process!');
  }
  $app->{breadcrumbs} = [ {
     bc_name => 'MT-Notifier > '.$app->translate('Data Import')
  } ];
  $app->build_page($notifier->load_tmpl('notification_request.tmpl'), {
    message => $message,
    notifier_version => version_number()
  });
}

sub notifier_loader {
  my $notifier = MT::Plugin::Notifier->instance;
  my $app = MT->instance;
  my $auth = ($app->user->is_superuser) ? 1 : 0;
  my $message;
  if ($auth) {
    if ($app->{cfg}->ObjectDriver =~ /^DBI::(.*)$/) {
      my $type = $1;
      my $cfg = MT::ConfigMgr->instance;
      my $dbh = MT::Object->driver->{dbh};
      my $schema = File::Spec->catfile('schemas', $type . '.dump');
      open FH, $schema or die "<p class=\"bad\">Can't open schema file '$schema': $!</p>";
      my $ddl;
      { local $/; $ddl = <FH> }
      close FH;
      my @stmts = split /;/, $ddl;
      for my $stmt (@stmts) {
        $stmt =~ s!^\s*!!;
        $stmt =~ s!\s*$!!;
        next unless $stmt =~ /\S/;
        $dbh->do($stmt) or die $dbh->errstr;
      }
      $message = $app->translate('Your system is installed and ready to use!');
    }
  } else {
    $message = $app->translate('You are not authorized to run this process!');
  }
  $app->{breadcrumbs} = [ {
     bc_name => 'MT-Notifier > '.$app->translate('Initial System Load')
  } ];
  $app->build_page($notifier->load_tmpl('notification_request.tmpl'), {
    message => $message,
    notifier_version => version_number()
  });
}

sub notifier_request {
  my $notifier = MT::Plugin::Notifier->instance;
  my $app = shift;
  my $cipher = $app->{query}->param('c');
  my $email = $app->{query}->param('email');
  my $o = $app->{query}->param('o');                  # opt-out flag
  my $u = $app->{query}->param('u');                  # unsubscribe
  my $redirect = $app->{query}->param('redirection'); # redirection
  my $blog_id = $app->{query}->param('blog_id');
  my $category_id = $app->{query}->param('category_id');
  my $entry_id = $app->{query}->param('entry_id');
  my ($data, $message);
  if ($cipher) {
    use Notifier::Data;
    $data = Notifier::Data->load({ cipher => $cipher });
    if ($data) {
      if ($o) {
        my $blog_id = $data->blog_id;
        my $category_id = $data->category_id;
        my $entry_id = $data->entry_id;
        my $email = $data->email;
        my $record = OPT;
        if ($entry_id) {
          my $entry = MT::Entry->load($entry_id);
          if ($entry) {
            $blog_id = $entry->blog_id;
          } else {
            $message =
              $app->translate('No entry was found to match that subscription record!');
          }
        } elsif ($category_id) {
          my $category = MT::Category->load($category_id);
          if ($category) {
            $blog_id = $category->blog_id;
          } else {
            $message =
              $app->translate('No category was found to match that subscription record!');
          }
        }
        $category_id = 0;
        $entry_id = 0;
        create_subscription($email, $record, $blog_id, $category_id, $entry_id);
        $message = $app->translate('Your opt-out record has been created!')
      } elsif ($u) {
        $data->remove;
        $message = $app->translate('Your subscription has been cancelled!')
      }
    } else {
      $message = $app->translate('No subscription record was found to match that locator!');
    }
    unless ($message) {
      $message = $app->translate('Your request has been processed successfully!');
      $data->status(RUNNING);
      $data->save;
    }
  } else {
    if ($email) {
      if ($blog_id || $category_id || $entry_id) {
        if ($entry_id) {
          $blog_id = 0;
          $category_id = 0;
        } elsif ($category_id) {
          $blog_id = 0;
          $entry_id = 0;
        } elsif ($blog_id) {
          $category_id = 0;
          $entry_id = 0;
        }
        my $error = create_subscription($email, SUB, $blog_id, $category_id, $entry_id);
        $message = $app->translate('The specified email address is not valid!')
          if ($error == 1);
        $message = $app->translate('The requested record key is not valid!')
          if ($error == 2);
        $message = $app->translate('Your request has been processed successfully!')
          unless ($error);
      } else {
        $message = $app->translate('Your request did not include a record key!');
      }
    } else {
      $message = $app->translate('Your request must include an email address!');
    }
  }
  $app->{breadcrumbs} = [ {
     bc_name => 'MT-Notifier > '.$app->translate('Subscription Request Processing')
  } ];
  $app->build_page($notifier->load_tmpl('notification_request.tmpl'), {
    message => $message,
    notifier_version => version_number(),
    redirect => $redirect
  });
}

# shared functions

sub create_subscription {
  my $notifier = MT::Plugin::Notifier->instance;
  my $app = MT->instance;
  my ($email, $record, $blog_id, $category_id, $entry_id, $bulk) = @_;
  my $blog;
  use MT::Blog;
  use MT::Util;
  if (my $fixed = MT::Util::is_valid_email($email)) {
    $email = $fixed;
  } else {
    return 1;
  }
  return unless ($record eq OPT || $record eq SUB);
  if ($blog_id) {
    $blog = MT::Blog->load($blog_id) or return 2;
  }
  if ($category_id) {
    use MT::Category;
    my $category = MT::Category->load($category_id) or return 2;
    $blog = MT::Blog->load($category->blog_id) or return 2;
  }
  if ($entry_id) {
    use MT::Entry;
    my $entry = MT::Entry->load($entry_id) or return 2;
    $blog = MT::Blog->load($entry->blog_id) or return 2;
  }
  my $data = Notifier::Data->load({
    blog_id => $blog_id,
    category_id => $category_id,
    entry_id => $entry_id,
    email => $email,
    record => $record
  });
  unless ($data) {
    $data = Notifier::Data->new;
    $data->blog_id($blog_id);
    $data->category_id($category_id);
    $data->entry_id($entry_id);
    $data->email($email);
    $data->record($record);
    $data->cipher(produce_cipher(
      'a'.$email.'b'.$blog_id.'c'.$category_id.'d'.$entry_id
    ));
    my $config = $notifier->get_config_hash();
    my $blog_config = $notifier->get_config_hash('blog:'.$blog->id);
    if ($config->{'system_confirm'} && $blog_config->{'blog_confirm'}) {
      $data->status(PENDING) unless ($bulk);
      $data->status(RUNNING) if ($bulk);
    } else {
      $data->status(RUNNING);
    }
    $data->save;
    data_confirmation($data) if ($data->status == PENDING);
  }
}

sub data_confirmation {
  my $notifier = MT::Plugin::Notifier->instance;
  my $app = MT->instance;
  my ($data) = @_;
  my $blog = MT::Blog->load($data->blog_id) or return;
  my ($category, $entry, $type);
  if ($data->entry_id) {
    $entry = MT::Entry->load($data->entry_id) or return;
    $type = $app->translate('Entry');
  } elsif ($data->category_id) {
    $category = MT::Category->load($data->category_id) or return;
    $type = $app->translate('Category');
  } else {
    $type = $app->translate('Blog');
  }
  my ($author, $lang);
  if ($entry) {
    $author = $entry->author;
    if ($author && $author->preferred_language) {
      $lang = $author->preferred_language;
      $app->set_language($lang);
    }
  }
  my $sender_address = load_sender_address($data, $author);
  return unless ($sender_address);
  use MT::ConfigMgr;
  my $cfg = MT::ConfigMgr->instance;
  $app->set_language($cfg->DefaultLanguage) unless ($lang);
  my $charset = $cfg->PublishCharset || 'iso-8859-1';
  my $record_text = ($data->record == SUB) ?
    $app->translate('subscribe to') :
    $app->translate('opt-out of');
  my %head = (
    'Content-Type' => qq(text/plain; charset="$charset"),
    'From' => $sender_address,
    'Subject' => '['.$blog->name.'] '
  );
  use MT::Util;
  my %param = (
    'blog_name' => MT::Util::remove_html($blog->name),
    'notifier_home' => $notifier->author_link,
    'notifier_name' => $notifier->name,
    'notifier_link' => $cfg->CGIPath.$notifier->envelope.'/mt-notifier.cgi',
    'notifier_version' => version_number(),
    'record_cipher' => $data->cipher,
    'record_text' => $record_text
  );
  if ($entry) {
    $head{'Subject-Pending'} =
      $app->translate("Please confirm your request to $record_text \'[_1]\'", $entry->title);
    $head{'Subject-Running'} =
      $app->translate("You have subscribed to $record_text \'[_1]\'", $entry->title);
    $param{'record_link'} = $entry->permalink;
    $param{'record_name'} = MT::Util::remove_html($entry->title);
  } elsif ($category) {
    $head{'Subject-Pending'} =
      $app->translate("Please confirm your request to $record_text \'[_1]\'", $category->label);
    $head{'Subject-Running'} =
      $app->translate("You have subscribed to $record_text \'[_1]\'", $category->label);
    my $link = $blog->archive_url;
    $link .= '/' unless $link =~ m/\/$/;
    $link .= MT::Util::archive_file_for ('',  $blog, $type, $category);
    $param{'record_link'} = $link;
    $param{'record_name'} = MT::Util::remove_html($category->label);
  } elsif ($blog) {
    $head{'Subject-Pending'} =
      $app->translate("Please confirm your request to $record_text \'[_1]\'", $blog->name);
    $head{'Subject-Running'} =
      $app->translate("You have subscribed to $record_text \'[_1]\'", $blog->name);
    $param{'record_link'} = $blog->archive_url;
    $param{'record_name'} = MT::Util::remove_html($blog->name);
  }
  $param{'status'} = $data->status;
  $param{'request_subject'} = ($param{'status'}) ?
    $head{'Subject-Running'} : $head{'Subject-Pending'};
  $head{'Subject'} .= $param{'request_subject'};
  $head{'To'} = $data->email;
  my $body = load_email('confirmation.tmpl', \%param);
  send_email(\%head, $body);
}

sub load_sender_address {
  my $notifier = MT::Plugin::Notifier->instance;
  my $app = MT->instance;
  my ($obj, $author) = @_;
  my $sender_address;
  my $config = $notifier->get_config_hash();
  if ($config) {
    if ($config->{'system_address_type'}) {
      $sender_address = $config->{'system_address'};
    } else {
      $sender_address = $author->email if ($author);
    }
  }
  my $blog_config = $notifier->get_config_hash('blog:'.$obj->blog_id);
  if ($blog_config) {
    if ($blog_config->{'blog_address_type'} == 2) {
      $sender_address = $author->email if ($author);
    } elsif ($blog_config->{'blog_address_type'} == 3) {
      $sender_address = $blog_config->{'blog_address'};
    }
  }
  use MT::Util;
  if (my $fixed = MT::Util::is_valid_email($sender_address)) {
    return $fixed;
  } else {
    my $message = 'MT-Notifier: ';
    if ($sender_address) {
      $message .= $app->translate('Invalid sender address - please reconfigure it!');
    } else {
      $message .= $app->translate('No sender address - please configure one!');
    }
    $app->log($message);
    return;
  }
}

sub load_email {
  my $notifier = MT::Plugin::Notifier->instance;
  my $app = MT->instance;
  my ($file, $param) = @_;
  my @paths;
  my $dir = File::Spec->catdir($app->mt_dir, $notifier->envelope, 'tmpl', 'email');
  push @paths, $dir if -d $dir;
  $dir = File::Spec->catdir($app->mt_dir, $notifier->envelope, 'tmpl');
  push @paths, $dir if -d $dir;
  $dir = File::Spec->catdir($app->mt_dir, $notifier->envelope);
  push @paths, $dir if -d $dir;
  require HTML::Template;
  my $tmpl;
  eval {
    local $1; ## This seems to fix a utf8 bug (of course).
    $tmpl = HTML::Template->new_file(
      $file,
      path => \@paths,
      search_path_on_include => 1,
      die_on_bad_params => 0,
      global_vars => 1);
  };
  return MT->trans_error("Loading template '[_1]' failed: [_2]", $file, $@) if $@;
  for my $key (keys %$param) {
    $tmpl->param($key, $param->{$key});
  }
  MT->translate_templatized($tmpl->output);
}

sub notify_users {
  my $notifier = MT::Plugin::Notifier->instance;
  my $app = MT->instance;
  my ($obj, $work_subs) = @_;
  my $blog = MT::Blog->load($obj->blog_id) or return;
  my ($entry, $comment, $type);
  if (UNIVERSAL::isa($obj, 'MT::Comment')) {
    $entry = MT::Entry->load($obj->entry_id) or return;
    $comment = $obj;
    $type = $app->translate('Comment');
  } else {
    $entry = $obj;
    $type = $app->translate('Entry');
  }
  my @work_opts =
    map { $_ }
    Notifier::Data->load({
      blog_id => $blog->id,
      record => OPT,
      status => RUNNING
    });
  my @places = MT::Placement->load({
    entry_id => $entry->id
  });
  foreach my $place (@places) {
    my @category_opts = Notifier::Data->load({
      category_id => $place->category_id,
      record => OPT,
      status => RUNNING
    });
    foreach (@category_opts) {
      push @work_opts, $_;
    }
  }
  my %opts = map { $_->email => 1 }@work_opts;
  my @subs = grep { !exists $opts{$_->email} } @$work_subs;
  my $users = scalar @subs;
  return unless ($users);
  my $author = $entry->author;
  my $sender_address = load_sender_address($obj, $author);
  return unless ($sender_address);
  $app->set_language($author->preferred_language)
    if ($author && $author->preferred_language);
  use MT::ConfigMgr;
  my $cfg = MT::ConfigMgr->instance;
  my $charset = $cfg->PublishCharset || 'iso-8859-1';
  my %head = (
    'Content-Type' => qq(text/plain; charset="$charset"),
    'From' => $sender_address,
    'Subject' => '['.$blog->name.'] '
  );
  if ($comment) {
    $head{'Subject'} .=
      $app->translate('New Comment from \'[_1]\' ', $comment->author).
      $app->translate('on \'[_1]\' ', $entry->title);
  } else {
    $head{'Subject'} .=
      $app->translate('New Entry \'[_1]\' ', $entry->title).
      $app->translate('from \'[_1]\'', $author->name);
  }
  use MT::Util;
  my %param = (
    'blog_name' => MT::Util::remove_html($blog->name),
    'entry_excerpt' => $entry->get_excerpt,
    'entry_id' => $entry->id,
    'entry_link' => $entry->permalink,
    'entry_title' => MT::Util::remove_html($entry->title),
    'notifier_home' => $notifier->author_link,
    'notifier_name' => $notifier->name,
    'notifier_link' => $cfg->CGIPath.$notifier->envelope.'/mt-notifier.cgi',
    'notifier_version' => version_number()
  );
  if ($comment) {
    $param{'comment_author'} = $comment->author;
    $param{'comment_url'} = $comment->url;
    $param{'comment_text'} = $comment->text;
    $param{'notifier_comment'} = 1,
    $param{'notifier_entry'} = 0
  } else {
    $param{'notifier_comment'} = 0,
    $param{'notifier_entry'} = 1
  }
  foreach my $sub (@subs) {
    next if ($comment && $sub->email eq $comment->email);
    $head{'To'} = $sub->email;
    $param{'record_cipher'} = $sub->cipher;
    my $body = load_email('notification.tmpl', \%param);
    send_email(\%head, $body);
  }
}

sub produce_cipher {
  my $key = shift;
  my $salt = join '', ('.', '/', 0..9, 'A'..'Z', 'a'..'z')[rand 64, rand 64];
  my $cipher = crypt ($key, $salt);
  $cipher =~ s/\.$/q/;
  $cipher;
}

sub send_email {
  my $notifier = MT::Plugin::Notifier->instance;
  my $app = MT->instance;
  my ($hdrs, $body) = @_;
  foreach my $h (keys %$hdrs) {
    if (ref($hdrs->{$h}) eq 'ARRAY') {
      map { y/\n\r/  / } @{$hdrs->{$h}};
    } else {
      $hdrs->{$h} =~ y/\n\r/  / unless (ref($hdrs->{$h}));
    }
  }
  $body .= "\n\n--\n";
  $body .= $notifier->name.' v'.$notifier->version."\n";
  $body .= $notifier->author_link."\n";
  use MT::Mail;    
  my $mgr = MT::ConfigMgr->instance;
  my $xfer = $mgr->MailTransfer;
  if ($xfer eq 'sendmail') {
    return MT::Mail->_send_mt_sendmail($hdrs, $body, $mgr);
  } elsif ($xfer eq 'smtp') {
    return MT::Mail->_send_mt_smtp($hdrs, $body, $mgr);
  } elsif ($xfer eq 'debug') {
    return MT::Mail->_send_mt_debug($hdrs, $body, $mgr);
  } else {
    return MT::Mail->error(MT->translate(
      "Unknown MailTransfer method '[_1]'", $xfer ));
  }
}

sub version_number {
  (my $ver = $VERSION) =~ s/^([\d]+[\.]?[\d]*).*$/$1/;
  $ver;
}

1;

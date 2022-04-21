package PerlDaemon::Logger;

use strict;
use warnings;

use POSIX qw(strftime);

$| = 1;

our $SELF;

$SIG{'USR2'} = sub {
  $SELF->flushlogs();
};

sub new ($$) {
  my ($class, $conf) = @_;

  die "Instance already exists" if defined $SELF;
  $SELF = bless { conf => $conf }, $class;
  $SELF->{queue} = [];

  return $SELF;
}

sub logmsg ($$) {
  my ($self, $msg) = @_;
  my $conf = $self->{conf};
  my $logline = localtime()." (PID $$): $msg\n";

  { lock $self->{queue};
    push @{$self->{queue}}, $logline;
  }

  $self->flushlogs();
  return undef;
}

sub flushlogs ($$) {
  my ($self, $msg) = @_;
  my $conf = $self->{conf};
  my $logfile = $conf->{'daemon.logfile'};

  { lock $self->{queue};
    open my $fh, ">>$logfile" or die "Can't write logfile $logfile: $!\n";
    for my $logline (@{$self->{queue}}) {
      print $fh $logline;
      print $logline if $conf->{'daemon.daemonize'} ne 'yes';
    }
    close $fh;
    @{$self->{queue}} = ();
  }

  return undef;
}

sub err ($$) {
  my ($self, $msg) = @_;
  $self->logmsg($msg);
  die "$msg\n";
}

sub warn ($$) {
  my ($self, $msg) = @_;
  $self->logmsg("WARNING: $msg");

  return undef;
}

sub rotatelog ($) {
  my $self = shift;
  my $conf = $self->{conf};
  my $logfile = $conf->{'daemon.logfile'};

  $self->logmsg('Rotating logfile');

  my $timestr = strftime "%Y%m%d-%H%M%S", localtime();
  `mv $logfile $logfile.$timestr`;

  return undef;
}

1;

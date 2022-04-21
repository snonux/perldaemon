#!/usr/bin/perl

# PerlDaemon (c) 2010, 2011, Dipl.-Inform. (FH) Paul Buetow (http://perldaemon.buetow.org)

use strict;
use warnings;

use POSIX qw(setsid strftime);
use Time::HiRes qw(gettimeofday tv_interval);

use PerlDaemon::Logger;
use PerlDaemon::RunModules;

$| = 1;

sub trimstr (@) {
  my @str = 
  @_;

  for (@str) {
    chomp;
    s/^[\t\s]+//;
    s/[\t\s]+$//;
  }

  return @str;
}

sub trunc ($) {
  my $file = shift;
  open my $fh, ">$file" or die "Can't write $file: $!\n";
  print $fh '';
  close $fh;
}

sub checkpid ($) {
  my $conf = shift;
  my $pidfile = $conf->{'daemon.pidfile'};
  my $logger = $conf->{logger};

  trunc $pidfile unless -f $pidfile;

  open my $fh, $pidfile or $logger->err("Can't read pidfile $pidfile: $!");
  my ($pid) = <$fh>;
  close $fh;

  if (defined $pid) {
    chomp $pid;
    $logger->err("Process with pid $pid already running") if 0 < int $pid && kill 0, $pid;
  }
}

sub writepid ($) {
  my $conf = shift;
  my $logger = $conf->{logger};

  my $pidfile = $conf->{'daemon.pidfile'};

  open my $fh, ">$pidfile" or $logger->err("Can't write pidfile: $!");
  print $fh "$$\n";
  close $fh;
}


sub readconf ($%) {
  my ($confile, %opts) = @_;
  my $desc;

  open my $fh, $confile or 
  die "Can't read config file $confile (specify using config=filepath)\n";

  my %conf;
  while (<$fh>) {
    if (/^#(.*)/) {
      $desc = $1;
      next;
    }

    next if /^[\t\w]+#/;
    s/#.*//;

    my ($key, $val) = trimstr split '=', $_, 2;
    next unless defined $val;

    $conf{$key} = $val; 

    if (defined $desc) {
      $conf{"$key.desc"} = $desc; 
      $desc = undef;
    }
  }

  close $fh;

  # Check
  my $msg = 'Missing property:';

  foreach (qw(wd loopinterval alivefile pidfile logfile daemonize)) {
    my $key = "daemon.$_";
    die "$msg $key\n" unless exists $conf{$key};
  }

  @conf{keys %opts} = values %opts;
  return \%conf;
}

sub daemonize ($) {
  my $conf = shift;
  my $logger = $conf->{logger};
  $logger->logmsg('Daemonizing...');

  chdir $conf->{'daemon.wd'} or $logger->err("Can't chdir to wd: $!");

  my $msg = 'Can\'t read /dev/null:';

  open STDIN, '>/dev/null' or $logger->err("$msg $!");
  open STDOUT, '>/dev/null' or $logger->err("$msg $!");
  open STDERR, '>/dev/null' or $logger->err("$msg $!");

  defined (my $pid = fork) or $logger->err("Can't fork: $!"); 
  exit if $pid;

  setsid or $logger->err("Can't start a new session: $!");

  writepid $conf;
  $logger->logmsg('Daemonizing completed');
}

sub sighandlers ($) {
  my $conf = shift;
  my $logger = $conf->{logger};

  $SIG{TERM} = sub {
    # On shutdown
    $logger->logmsg('Received SIGTERM. Shutting down....');
    unlink $conf->{'daemon.pidfile'} if -f $conf->{'daemon.pidfile'};
    exit 0;
  };

  $SIG{HUP} = sub {
    # On logrotate
    $logger->logmsg('Received SIGHUP.');
    $logger->rotatelog();
  };
}

sub prestartup ($) {
  my $conf = shift;
  checkpid $conf;
}

sub alive ($) {
  my $conf = shift;
}

sub daemonloop ($) {
  my $conf = shift;
  my $rmodule = PerlDaemon::RunModules->new($conf);
  my $loopinterval = $conf->{'daemon.loopinterval'};

  my $loop = shift;
  my $lastrun = [0,0];

  for (;;) {
    my $now = [gettimeofday];
    my $timediff = tv_interval($lastrun, $now);

    if ($timediff >= $loopinterval) {
      $lastrun = $now;                                
      $rmodule->do();
      alive $conf;
    }

    sleep $loopinterval / 10;
  }
}

sub showkeys ($) {
  my $conf = shift;
  for my $key (grep !/(^keys$)|(^config$)|(\.desc$)/, keys %$conf) {
    print '#' . (exists $conf->{"$key.desc"}
      ?  $conf->{"$key.desc"} 
      : ' Undocumented property');
    print "\n$key=$conf->{$key}\n\n";
  }
}

sub getopts (@) {
  my %opts;

  for my $opt (@_) {
    next unless $opt =~ /=/;
    my ($key, $val) = split '=', $opt, 2;
    $opts{$key} = $val;
  }

  return %opts;
}

my %opts = getopts @ARGV;

my $conf = readconf $opts{config}, %opts;

if (exists $conf->{keys}) {
  showkeys($conf);
  exit 0;
}

$conf->{logger} = PerlDaemon::Logger->new($conf);

prestartup $conf;

if ($conf->{'daemon.daemonize'} ne 'yes') {
  print "Running in foreground...\n";
} else {
  daemonize $conf;
}

sighandlers $conf;
daemonloop $conf;



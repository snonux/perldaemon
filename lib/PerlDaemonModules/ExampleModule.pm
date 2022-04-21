package PerlDaemonModules::ExampleModule;

use strict;
use warnings;

sub new ($$$) {
  my ($class, $conf) = @_;

  my $self = bless { conf => $conf }, $class;
  # Store some private persistent module stuff
  $self->{counter} = 0;

  return $self;
}

# Runs periodically in a loop (set interval in perldaemon.conf)
sub do ($) {
  my $self = shift;
  my $conf = $self->{conf};
  my $logger = $conf->{logger};

  # Calculate some private module stuff
  my $count = ++$self->{counter};

  $logger->logmsg("ExampleModule Test $count");
}

1;

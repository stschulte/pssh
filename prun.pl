#!/usr/bin/perl

# this script runs multiple ssh commands in parallel and
# will inform you about the return codes. It will also
# create one logfile for each ssh command
#
# The machines and commands are read from STDIN. The input is
# parsed line by line. The first column will be interpreted as
# the remote host while the rest of the line (seperated with
# whitespace) is treated as the commandline that should be
# excecuted on the remote host
#
# Example:
# 
# Create a file with the following content
#
# host01.example.com echo "Updating"; yum -y upgrade
# host02.example.com echo "Updating"; yum -y upgrade
#
# and then run the perlscript like this
# ./prun.pl < input_file

use warnings;
use strict;

use Term::ANSIColor qw(:constants);

use constant MAX_FORKS => 50;

my %running;
my %failed;
my %success;
my $count = 0;

sub spaw_child {
  my($hostname, $command) = @_;

  if(my $pid = fork()) {
    my $child = {
      'hostname' => $hostname,
      'pid'      => $pid,
      'rc'       => -1,
    };
    return $child;
  }

  print "Execute ", BOLD, $command, RESET, " on ", GREEN, $hostname, RESET, "...\n";
  open STDOUT, '>', "${hostname}.out";
  open STDERR, '>&', STDOUT;
  close STDIN;
  exec '/usr/bin/ssh', '-n', '-oPreferredAuthentications=publickey',
    '-oStrictHostKeyChecking=yes', $hostname, $command;
  exit 12;
}

sub process_child {
  my $pid = wait();
  return -1 if $pid == -1;

  my $rc = $? >> 8;

  if (exists($running{$pid})) {
    my $child = $running{$pid};
    $child->{'rc'} = $rc;
    if ($rc == 0) {
      $success{$pid} = $child;
    }
    else {
      $failed{$pid} = $child;
    }
    delete $running{$pid};
    print "Finished (", BOLD, YELLOW, $count - scalar(keys %running), RESET, " of ",
      BOLD, YELLOW, $count, RESET, ") ",
      GREEN, $child->{'hostname'}, RESET,
      " (rc=", ($rc == 0 ? GREEN : RED), BOLD, $rc, RESET, ")\n";
  }
  return 1;
}

while(<>) {
  chomp;
  next if /^\s*#/;
  next if /^\s*$/;

  if(m/^(\S+)\s+(.+)$/) {
    my $hostname = $1;
    my $command = $2;

    while(scalar(keys %running) >= MAX_FORKS) {
      process_child();
    }

    my $child = spaw_child($hostname, $command);
    my $pid = $child->{'pid'};
    $running{$pid} = $child;
    $count++;
  }
  else {
    print "Invalid content \"$_\" at line $.. Ignore this line\n";
  }
}

while(process_child() != -1){
}

print "Everyone died ;-)\n";

if(scalar(keys %failed)) {
  print "\n";
  print "Summary: ", BOLD, YELLOW, scalar(keys %failed), RESET, " of ", BOLD, YELLOW, $count, RESET, " systems failed:\n";
  foreach my $key (sort keys %failed) {
    print " ", RED, "*", RESET, " ", GREEN, $failed{$key}->{'hostname'}, RESET, " (rc=", BOLD, RED, $failed{$key}->{'rc'}, RESET, ")\n";
  }
}

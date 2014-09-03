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

my %children;
my %running;
my %failed;
my %success;
my $count = 0;

while(<>) {
  chomp;
  if(m/^(\S+)\s+(.+)$/) {
    my $hostname = $1;
    my $command = $2;

    if(my $pid = fork()) {
      $children{$pid} = {
        'hostname' => $hostname,
        'pid'      => $pid,
        'rc'       => -1,
      };
      $running{$pid} = $children{$pid};
      $count++;
    }
    elsif(defined $pid) {
      print "Execute ", BOLD, $command, RESET, " on ", GREEN, $hostname, RESET, "...\n";
      open STDOUT, '>', "${hostname}.out";
      open STDERR, '>&', STDOUT;
      close STDIN;
      exec '/usr/bin/ssh', '-n', '-oPreferredAuthentications=publickey',
        '-oStrictHostKeyChecking=yes', $hostname, $command;
      exit 12;
    }
  }
  else {
    print "Invalid content \"$_\" at line $.. Ignore this line\n";
  }
}

while(my $pid = wait()) {
  last if $pid == -1;
  my $rc = $? >> 8;

  if (exists($children{$pid})) {
    $children{$pid}->{'rc'} = $rc;
    delete $running{$pid};
    if ($rc == 0) {
      $success{$pid} = $children{$pid};
    }
    else {
      $failed{$pid} = $children{$pid};
    }
    print "Finished (", BOLD, YELLOW, $count - scalar(keys %running), RESET, " of ",
      BOLD, YELLOW, $count, RESET, ") ",
      GREEN, $children{$pid}->{'hostname'}, RESET,
      " (rc=", ($rc == 0 ? GREEN : RED), BOLD, $rc, RESET, ")\n";
  }
}
print "Everyone died ;-)\n"

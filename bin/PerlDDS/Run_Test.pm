# $Id$

# This module contains a few miscellaneous functions and some
# startup ARGV processing that is used by all tests.

use PerlACE::Run_Test;
use PerlDDS::Process;
use PerlDDS::ProcessFactory;
use Cwd;

package PerlDDS;

sub orbsvcs {
  my $o = "$ENV{'TAO_ROOT'}/orbsvcs";
  my $n = -r "$o/Naming_Service/tao_cosnaming" || # using new names?
          -r "$o/Naming_Service/tao_cosnaming.exe" ||
          -r "$o/Naming_Service/Release/tao_cosnaming.exe";
  return (
    'Naming_Service' => "$o/Naming_Service/" . ($n ? 'tao_cosnaming'
                                                   : 'Naming_Service'),
    'ImplRepo_Service' => "$o/ImplRepo_Service/" . ($n ? 'tao_imr_locator'
                                                       : 'ImplRepo_Service'),
    'ImR_Activator' => "$o/ImplRepo_Service/" . ($n ? 'tao_imr_activator'
                                                    : 'ImR_Activator'),
    );
}

sub formatted_time {
  my $seconds = shift;

  my $sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst;
  if (defined($seconds)) {
    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
      localtime($seconds);
  } else {
    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
      localtime;
  }
  $year += 1900;
  my $time_str = "$year-$mon-$mday $hour:$min:$sec";
  return $time_str;
}

sub wait_kill {
  my $process = shift;
  my $wait_time = shift;
  my $desc = shift;
  my $verbose = shift;
  $verbose = 0 if !defined($verbose);

  my $ret_status = 0;
  my $start_time = formatted_time;
  if ($verbose) {
    print STDERR "$start_time: waiting $wait_time for $desc before calling kill\n";
  }
  my $result = $process->WaitKill($wait_time);
  my $time_str = formatted_time;
  if ($result != 0) {
      my $ext = ($verbose ? "" : "(started at $start_time)");
      print STDERR "$time_str: ERROR: $desc returned $result $ext\n";
      $ret_status = 1;
  } elsif ($verbose) {
    print STDERR "$time_str: shut down subscriber #1\n";
  }
  return $ret_status;
}

sub terminate_wait_kill {
  my $process = shift;
  my $wait_time = shift;
  my $desc = shift;
  $wait_time = 10 if !defined($wait_time);
  $desc = "DCPSInfoRepo" if !defined($desc);

  my $result = $process->TerminateWaitKill($wait_time);
  my $ret_status = 0;
  my $time_str = formatted_time;
  if ($result != 0) {
      print STDERR "$time_str: ERROR: $desc returned $result\n";
      $ret_status = 1;
  }
  return $ret_status;
}

sub print_file {
  my $file = shift;

  if (open FILE, "<", $file) {
      print "$file:\n";
      while (my $line = <FILE>) {
          print "$line";
      }
      print "\n\n";
      close FILE;
  }
}

# load gcov helpers in case this is a coverage build
my $config = new PerlACE::ConfigList;
$PerlDDS::Coverage_Test = $config->check_config("Coverage");

# used to prevent multiple special processes from running remotely
$PerlDDS::Special_Process_Created = 0;

$PerlDDS::Coverage_Count = 0;
$PerlDDS::Coverage_MAX_COUNT = 6;
$PerlDDS::Coverage_Overflow_Count = $PerlDDS::Coverage_MAX_COUNT;
$PerlDDS::Coverage_Processes = [];

# used for VxWorks
$PerlDDS::vxworks_test_target = undef;
$PerlDDS::added_lib_path = "";

sub return_coverage_process {
  my $count = shift;
  if ($count >= $PerlDDS::Coverage_Count) {
    print STDERR "return_coverage_process called with $count, but only" .
      ($PerlDDS::Coverage_Count - 1) . " processes have been created.\n";
    return;
  }
  $PerlDDS::Coverage_Processes->[$count] = 0;
}

sub next_coverage_process {
  my $next;
  for ($next = 0; $next < $PerlDDS::Coverage_MAX_COUNT; ++$next) {
    if (!$PerlDDS::Coverage_Processes->[$next]) {
      $PerlDDS::Coverage_Processes->[$next] = 1;
      return $next;
    }
  }
  ++$PerlDDS::Coverage_Overflow_Count;
  $next = $PerlDDS::Coverage_MAX_COUNT - 1;
  print STDERR "ERROR: maximum coverage processes reached, " .
    "$PerlDDS::Coverage_Overflow_Count processes active.\n";

  return $next;
}

sub is_coverage_test()
{
  return $PerlDDS::Coverage_Test;
}

sub is_special_process_created()
{
  return $PerlDDS::Special_Process_Created;
}

sub special_process_created()
{
  $PerlDDS::Special_Process_Created = 1;
}

sub get_test_target_config_name()
{
    # could refactor out of PerlACE::create_target
    my $component = shift;

    my $envname = "DOC_TEST_\U$component";
    if (!exists $ENV{$envname}) {
        # no test target config name
        return undef;
    }
    my $config_name = $ENV{$envname};
    # There's a configuration name
    $config_name = uc $config_name;
    return $config_name;
}

sub get_test_target_os()
{
    # could refactor out of PerlACE::create_target
    my $config_name = shift;

    $envname = $config_name.'_OS';
    if (!exists $ENV{$envname}) {
        print STDERR "$config_name requires an OS type in $envname\n";
        return undef;
    }
    my $config_os = $ENV{$envname};
    return $config_os;
}

sub create_test_target()
{
    # could refactor out of PerlACE::create_target
    my $config_name = shift;
    my $config_os = shift;

    my $target = undef;
    SWITCH: {
      if ($config_os =~ m/local|remote/i) {
        $target = new PerlACE::TestTarget ($config_name);
        last SWITCH;
      }
      if ($config_os =~ m/LabVIEW_RT/i) {
        require PerlACE::TestTarget_LVRT;
        $target = new PerlACE::TestTarget_LVRT ($config_name);
        last SWITCH;
      }
      if ($config_os =~ /VxWorks/i) {
        require PerlACE::TestTarget_VxWorks;
        $target = new PerlACE::TestTarget_VxWorks ($config_name);
        last SWITCH;
      }
      if ($config_os =~ /WinCE/i) {
        require PerlACE::TestTarget_WinCE;
        $target = new PerlACE::TestTarget_WinCE ($config_name);
        last SWITCH;
      }
      if ($config_os =~ /ANDROID/i) {
        require PerlACE::TestTarget_Android;
        $target = new PerlACE::TestTarget_Android ($config_name, $component);
        last SWITCH;
      }
      print STDERR "$config_os is an unknown OS type!\n";
    }
    return $target;
}

sub swap_path {
    my $name   = shift;
    my $new_value  = shift;
    my $orig_value  = shift;
    my $environment = $ENV{$name};
    $environment =~ s/$orig_value/$new_value/g;
    $ENV{$name} = $environment;
}

sub swap_lib_path {
    my($new_value) = shift;
    my($orig_value) = shift;

  # Set the library path supporting various platforms.
    swap_path('PATH', $new_value, $orig_value);
    swap_path('DYLD_LIBRARY_PATH', $new_value, $orig_value);
    swap_path('LD_LIBRARY_PATH', $new_value, $orig_value);
    swap_path('LIBPATH', $new_value, $orig_value);
    swap_path('SHLIB_PATH', $new_value, $orig_value);
}

sub add_lib_path {
    my($dir) = shift;

    # add the cwd to the directory if it is relative
    if (($dir =~ /^\.\//) || ($dir =~ /^\.\.\//)) {
      $dir = Cwd::getcwd() . "/$dir";
    }

    PerlACE::add_lib_path($dir);

    if (defined($PerlDDS::vxworks_test_target)) {
        $PerlDDS::vxworks_test_target->AddLibPath($dir);
    }
    elsif (PerlACE::is_vxworks_test()) {
        # store added lib path for late created TestTargets
        $PerlDDS::added_lib_path .= $dir . ':';
    }
}

# Add PWD to the load library path
add_lib_path ('.');

$sleeptime = 5;

package PerlDDS::TestFramework;
use strict;

sub new {
  my $class = shift;
  print STDERR "TestFramework created\n";
  my $self = bless {}, $class;

  $self->{processes} = {};
  $self->{flags} = {};
  $self->{status} = 0;
  $self->{log_files} = [];
  $self->{info_repo} = {};
  $self->{info_repo}->{executable} = "$ENV{DDS_ROOT}/bin/DCPSInfoRepo";
  $self->{info_repo}->{state} = "none";
  $self->{info_repo}->{file} = "repo.ior";
  $self->{processes}->{process} = {};
  $self->{processes}->{order} = [];
  $self->{discovery} = "info_repo";
  $self->{test_verbose} = 0;
  $self->{finished} = 0;

  my $index = 0;
  foreach my $arg (@ARGV) {
    $self->{flags}->{$arg} = $index;
    if ($arg =~ /^rtps_disc(?:_tcp)?$/) {
      $self->{discovery} = "rtps";
    } elsif ($arg eq "--test_verbose") {
      $self->{test_verbose} = 1;
      print STDERR _prefix() . "Test starting\n";
    } else {
      # also keep a copy to delete so we can see which parameters
      # are unused (above args are already "used")
      $self->{flags}->{unused}->{$arg} = $index;
    }
    ++$index;
  }

  return $self;  
}

sub DESTROY
{
}

sub finish {
  my $self = shift;
  my $wait_to_kill = shift;
  my $first_process_to_stop = shift;
  if ($self->{test_verbose}) {
    print STDERR "TestFramework::finish finished=$self->{finished}, "
      . "status=$self->{status}\n";
  }
  
  if ($self->{finished}) {
    return;
  }
  $self->{finished} = 1;
  
  if (defined($wait_to_kill)) {
    $self->stop_processes($wait_to_kill, $first_process_to_stop);
  }
  if ($self->{status} == 0) {
    print STDERR _prefix() . "test PASSED.\n";
  } else {
    foreach my $file (@{$self->{log_files}}) {
      print_file($file);
    }
    print STDERR _prefix() . "test FAILED.\n";
  }

  unlink $self->{info_repo}->{file};

  return $self->{status};
}

sub flag {
  my $self = shift;
  my $flag_passed = shift;

  my $present = defined($self->{flags}->{$flag_passed});
  if ($present) {
    delete($self->{flags}->{unused}->{$flag_passed});
  }
  return $present;
}

sub report_unused_flags {
  my $self = shift;
  my $exit_if_unidentified = shift;
  $exit_if_unidentified = 0 if !defined($exit_if_unidentified);

  if ($self->{test_verbose}) {
    print STDERR "TestFramework::report_unused_flags\n";
  }
  my @unused = keys(%{$self->{flags}->{unused}});
  if (scalar(@unused) == 0) {
    return;
  }

  my $list = "";
  for my $key (@unused) {
    if ($list ne "") {
      $list .= ", ";
    }
    $list .= $key;
  }
  my $indication = ($exit_if_unidentified ? "ERROR" : "WARNING");
  print STDERR "$indication: unused command line arguments: $list\n";
  if ($exit_if_unidentified) {
    $self->{status} = -1;
    exit $self->finish();
  }
}

sub unused_flags {
  my $self = shift;
  
  return keys(%{$self->{flags}->{unused}});
}

sub process {
  my $self = shift;
  my $name = shift;
  my $executable = shift;
  my $params = shift;
  if (defined($self->{processes}->{process}->{$name})) {
    print STDERR "ERROR: already created process named \"$name\"\n";
    $self->{status} = -1;
    return;
  }
  $self->{processes}->{process}->{$name}->{process} =
    $self->_create_process($executable, $params);
}

sub setup_discovery {
  my $self = shift;
  my $params = shift;
  my $executable = shift;
  $executable = "$ENV{DDS_ROOT}/bin/DCPSInfoRepo" if !defined($executable);
  if ($self->{discovery} ne "info_repo") {
    if ($self->{test_verbose}) {
      print STDERR "TestFramework::setup_discovery not creating DCPSInfoRepo " .
        "since discovery=" . $self->{discovery} . "\n";
    }
    return;
  }

  if ($self->{info_repo}->{state} ne "none" &&
      $self->{info_repo}->{state} ne "shutdown") {
    print STDERR "ERROR: cannot start DCPSInfoRepo from a state of " .
      $self->{info_repo}->{state} . "\n";
    $self->{status} = -1;
  }

  $self->{info_repo}->{state} = "started";

  if ($params =~ /^(?:.* )?-o ([^ ]+)/) {
    $self->{info_repo}->{file} = $1;
  } else {
    $params .= " -o $self->{info_repo}->{file}";
  }
  unlink $self->{info_repo}->{file};

  $self->{info_repo}->{process} =
    $self->_create_process($executable, $params);

  print $self->{info_repo}->{process}->CommandLine() . "\n";
  $self->{info_repo}->{process}->Spawn();

  if (PerlACE::waitforfile_timed($self->{info_repo}->{file}, 30) == -1) {
    print STDERR "ERROR: waiting for $executable IOR file\n";
    $self->{status} = -1;
    exit $self->finish();
  }
}

sub start_process {
  my $self = shift;
  my $name = shift;

  if (!defined($self->{processes}->{process}->{$name})) {
    print STDERR "ERROR: no process with name=$name\n";
    $self->{status} = -1;
    return;
  }

  push(@{$self->{processes}->{order}}, $name);
  my $process = $self->{processes}->{process}->{$name}->{process};
  print $process->CommandLine() . "\n";
  $process->Spawn();
}

sub stop_process {
  my $self = shift;
  my $timed_wait = shift;
  my $name = shift;

  if (!defined($self->{processes}->{process}->{$name})) {
    print STDERR "ERROR: no process with name=$name\n";
    $self->{status} = -1;
    return;
  }

  # remove $name from the order list
  my @order = @{$self->{processes}->{order}};
  $self->{processes}->{order} = [];
  foreach my $list_name (@order) {
    if ($list_name ne $name) {
      push(@{$self->{processes}->{order}}, $list_name);
    }
  }

  $self->{status} |=
    PerlDDS::wait_kill($self->{processes}->{process}->{$name}->{process},
                       $timed_wait,
                       $name);
  delete($self->{processes}->{process}->{$name});
}

sub stop_processes {
  my $self = shift;
  my $timed_wait = shift;
  # if passed, this will be the first processed WaitKilled
  my $name = shift;
  
  if (!defined($timed_wait)) {
    print STDERR "ERROR: TestFramework::stop_processes need to provide time "
      . "to wait as first parameter passed.\n";
    $self->{status} = -1;
    return;
  }

  if ($self->{test_verbose}) {
    print STDERR "TestFramework::stop_processes\n";
  }

  while (scalar(@{$self->{processes}->{order}}) > 0) {
    if (!defined($name)) {
      my @rorder = reverse(@{$self->{processes}->{order}});
      $name = $rorder[0];
    }
    if ($self->{test_verbose}) {
      print STDERR "TestFramework::stop_processes stopping $name in $timed_wait seconds\n";
    }
    $self->stop_process($timed_wait, $name);
    # make next loop
    $name = undef;
    $timed_wait = 15;
  }

  $self->stop_discovery($timed_wait);
}

sub stop_discovery {
  my $self = shift;
  my $timed_wait = shift;
  my $name = "DCPSInfoRepo";

  if ($self->{test_verbose}) {
    print STDERR "TestFramework::stop_discovery in $timed_wait seconds\n";
  }

  if ($self->{discovery} ne "info_repo") {
    if ($self->{test_verbose}) {
      print STDERR "TestFramework::stop_discovery no discovery to stop " .
        "since discovery=" . $self->{discovery} . "\n";
    }
    return;
  }
  
  if (!defined($self->{info_repo}->{state}) ||
       $self->{info_repo}->{state} eq "shutdown") {
    my $state = (!defined($self->{info_repo}->{state}) ? "" : $self->{info_repo}->{state});
    print STDERR "ERROR: TestFramework::stop_discovery cannot stop $name " .
      "since its state=$state\n";
    $self->{status} = -1;
    return;
  }

  $self->{status} |=
    PerlDDS::terminate_wait_kill($self->{info_repo}->{process},
                                 $timed_wait,
                                 $name,
                                 $self->{test_verbose});
}

sub _prefix {
  my $self = shift;
  my $str = "";
  if ($self->{test_verbose}) {
    my $time_str = PerlDDS::formatted_time();
    $str = "$time_str: ";
  }
  return $str;
}

sub _track_log_files {
  my $self = shift;
  my $data = shift;

  if ($data =~ /-ORBLogFile ([^ ]+)/) {
    my $file = $1;
    if ($self->{test_verbose}) {
      print STDERR "TestFramework::_track_log_files found file=\"$file\"\n";
    }
    push(@{$self->log_files}, $file);
  }
}

sub _create_process {
  my $self = shift;
  my $executable = shift;
  my $params = shift;

  if ($self->{test_verbose}) {
    print STDERR "TestFramework::_create_process creating executable="
      . "$executable w/ params=$params\n";
  }
  _track_log_files($params);
  return
    PerlDDS::create_process($executable, $params);
}

1;

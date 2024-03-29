#!/usr/bin/perl
# check_ipmi_sensor: Nagios/Icinga plugin to check IPMI sensors
#
# Copyright (C) 2009-2015 Thomas-Krenn.AG,
# additional contributors see changelog.txt
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, see <http://www.gnu.org/licenses/>.
#
################################################################################
# The following guides provide helpful information if you want to extend this
# script:
#   http://tldp.org/LDP/abs/html/ (Advanced Bash-Scripting Guide)
#   http://www.gnu.org/software/gawk/manual/ (Gawk: Effective AWK Programming)
#   http://de.wikibooks.org/wiki/Awk (awk Wikibook, in German)
#   http://nagios.sourceforge.net/docs/3_0/customobjectvars.html (hints on
#                  custom object variables)
#   http://nagiosplug.sourceforge.net/developer-guidelines.html (plug-in
#                  development guidelines)
#   http://nagios.sourceforge.net/docs/3_0/pluginapi.html (plugin API)
################################################################################
use strict;
use warnings;
use Getopt::Long qw(:config no_ignore_case);
use IPC::Run qw( run ); #interact with processes
################################################################################
# set text variables
our $check_ipmi_sensor_version = "3.9";

sub get_version
{
    return <<EOT;
check_ipmi_sensor version $check_ipmi_sensor_version
Copyright (C) 2009-2015 Thomas-Krenn.AG
Current updates at http://git.thomas-krenn.com/check_ipmi_sensor_v3.git
EOT
}
sub get_usage
{
    return <<EOT;
Usage:
check_ipmi_sensor -H <hostname>
  [-f <FreeIPMI config file> | -U <username> -P <password> -L <privilege level>]
  [-O <FreeIPMI options>] [-b] [-T <sensor type>] [-x <sensor id>]
  [-i <sensor id>] [-o zenoss] [-D <protocol LAN version>] [-h] [-V]
  [-fc <num_fans>] [--fru] [--nosel] [--nothresholds] [--nosudo]
  [-v|-vv|-vvv]
EOT
}
sub get_help
{
    return <<EOT;
  [-H <hostname>]
       hostname or IP of the IPMI interface.
       For \"-H localhost\" or if no host is specified (local computer) the
       Nagios/Icinga user must be allowed to run
       ipmimonitoring/ipmi-sensors/ipmi-sel/[ipmi-fru] with root privileges
       or via sudo (ipmimonitoring/ipmi-sensors/ipmi-sel/[ipmi-fru] must be
       able to access the IPMI devices via the IPMI system interface).
  [-f <FreeIPMI config file>]
       path to the FreeIPMI configuration file.
       Only neccessary for communication via network.
       Not neccessary for access via IPMI system interface (\"-H localhost\").
       It should contain IPMI username, IPMI password, and IPMI privilege-level,
       for example:
         username monitoring
         password yourpassword
         privilege-level user
       As alternative you can use -U/-P/-L instead (see below).
  [-U <username> -P <password> -L <privilege level>]
       IPMI username, IPMI password and IPMI privilege level, provided as
       parameters and not by a FreeIPMI configuration file. Useful for RHEL/
       Centos 5.* with FreeIPMI 0.5.1 (this elder FreeIPMI version does not
       support config files).
       Warning: with this method the password is visible in the process list.
                So whenever possible use a FreeIPMI confiugration file instead.
  [-O <FreeIPMI options>]
       additional options for FreeIPMI. Useful for RHEL/CentOS 5.* with
       FreeIPMI 0.5.1 (this elder FreeIPMI version does not support config
       files).
  [-b]
       backward compatibility mode for FreeIPMI 0.5.* (this omits the FreeIPMI
       caching options --quiet-cache and --sdr-cache-recreate)
  [-T <sensor type>]
       limit sensors to query based on IPMI sensor type.
       Examples for IPMI sensor types are 'Fan', 'Temperature', 'Voltage', ...
       See the output of the FreeIPMI command 'ipmi-sensors -L' and chapter
       '42.2 Sensor Type Codes and Data' of the IPMI 2.0 spec for a full list
       of possible sensor types. The available types depend on your particular
       server and the available sensors there.
  [-x <sensor id>]
       exclude sensor matching <sensor id>. Useful for cases when unused
       sensors cannot be deleted from SDR and are reported in a non-OK state.
       Option can be specified multiple times. The <sensor id> is a numeric
       value (sensor names are not used as some servers have multiple sensors
       with the same name). Use -vvv option to query the <sensor ids>.
  [-i <sensor id>]
       include only sensor matching <sensor id>. Useful for cases when only
       specific sensors should be monitored. Be aware that only for the
       specified sensor errors/warnings are generated. Use -vvv option to query
       the <sensor ids>.
  [-v|-vv|-vvv]
       be verbose
         (no -v) .. single line output
         -v   ..... single line output with additional details for warnings
         -vv  ..... multi line output, also with additional details for warnings
         -vvv ..... debugging output, followed by normal multi line output
  [-o]
       change output format. Useful for using the plugin with other monitoring
       software than Nagios or Icinga.
         -o zenoss .. create ZENOSS compatible formatted output (output with
                      underscores instead of whitespaces and no single quotes)
  [-D]
       change the protocol LAN version. Normally LAN_2_0 is used as protocol
       version if not overwritten with this option. Use 'default' here if you
       don't want to use LAN_2_0.
  [-fc <num fans>]
       number of fans that should be active. If the number of current active
       fans reported by IPMI is smaller than <num fans> then a Warning state
       is returned.
  [--fru]
       print the product serial number if it is available in the IPMI FRU data.
       For this purpose the tool 'ipmi-fru' is used. E.g.:
         IPMI Status: OK (9000096781)
  [--nosel]
       turn off system event log checking via ipmi-sel. If there are
       unintentional entries in SEL, use 'ipmi-sel --clear'.
  [-sx|--selexclude <sel exclude file>]
       use a sel exclude file to exclude entries from the system event log.
       Specify name and type pipe delimitered in this file to exclude an entry,
       for example: System Chassis Chassis Intru|Physical Security
       To get valid names and types use the -vvv option and take a look at:
       debug output for sel (-vvv is set). Don't use name and type from the
       web interface as sensor descriptions are not complete there.
  [-xx|--sexclude <exclude file>]
       use an exclude file to exclude sensors.
       Specify name and type pipe delimitered in this file to exclude a sensor,
       To get valid names and types use the -vvv option.
  [--nosudo]
       turn off sudo usage on localhost or if ipmi host is ommited.
  [--nothresholds]
       turn off performance data thresholds from output-sensor-thresholds.
  [-s <ipmi-sensor output file>]
       simulation mode - test the plugin with an ipmi-sensor output redirected
       to a file.
  [-h]
       show this help
  [-V]
       show version information

Examples:
  \$ check_ipmi_sensor -H 192.0.2.1 -U monitor -P monitor -L user
    IPMI Status: OK | 'System Temp'=30.00 'Peripheral Temp'=32.00
    'FAN 1'=2775.00 [...]
  \$ check_ipmi_sensor -H 192.0.2.1 -U monitor -P monitor -L user -x 205
    IPMI Status: OK | 'System Temp'=30.00 'Peripheral Temp'=32.00
    'FAN 2'=2775.00 [...]
  \$ check_ipmi_sensor -H 192.0.2.1 -U monitor -P monitor -L user -i 4,71
    IPMI Status: OK | 'System Temp'=30.00 'Peripheral Temp'=32.00
  \$ check_ipmi_sensor -H 192.0.2.1 -U monitor -P monitor -L user -i 4 --fru
    IPMI Status: OK (0000012345) | 'System Temp'=30.00

Further information about this plugin can be found at
http://www.thomas-krenn.com/en/wiki/IPMI_Sensor_Monitoring_Plugin

Send email to the IPMI-plugin-user mailing list if you have questions regarding
use of this software, to submit patches, or suggest improvements.
The mailing list is available at http://lists.thomas-krenn.com/
EOT
}
sub usage
{
    my ($arg) = @_; #the list of inputs
    my ($exitcode);
    if ( defined $arg ){
        if ( $arg =~ m/^\d+$/ ){
            $exitcode = $arg;
        }
        else{
            print STDOUT $arg, "\n";
            $exitcode = 1;
        }
    }
    print STDOUT get_usage();
    exit($exitcode) if defined $exitcode;
}
################################################################################
# set ipmimonitoring path
our $MISSING_COMMAND_TEXT = '';
our $IPMICOMMAND ="";
if(-x "/usr/sbin/ipmimonitoring"){
    $IPMICOMMAND = "/usr/sbin/ipmimonitoring";
}
elsif (-x "/usr/bin/ipmimonitoring"){
    $IPMICOMMAND = "/usr/bin/ipmimonitoring";
}
elsif (-x "/usr/local/sbin/ipmimonitoring"){
    $IPMICOMMAND = "/usr/local/sbin/ipmimonitoring";
}
elsif (-x "/usr/local/bin/ipmimonitoring"){
    $IPMICOMMAND = "/usr/local/bin/ipmimonitoring";
}
else{
    $MISSING_COMMAND_TEXT = " ipmimonitoring/ipmi-sensors command not found!\n";
}

# Identify the version of the ipmi-tool
sub get_ipmi_version{
    my @ipmi_version_output = '';
    my $ipmi_version = '';
    @ipmi_version_output = `$IPMICOMMAND -V`;
    $ipmi_version = shift(@ipmi_version_output);
    $ipmi_version =~ /(\d+)\.(\d+)\.(\d+)/;
    @ipmi_version_output = ();
    push @ipmi_version_output,$1,$2,$3;
    return @ipmi_version_output;
}

sub simulate{
    my $output = '';
    my $simul_file = $_[0];
    if( !defined $simul_file || (-x '\"'.$simul_file.'\"')){
        print "DEBUG: Using simulation file: $simul_file\n";
        print "Error: Simulation file with ipmi output not found.\n";
        exit(3);
    }
    return ($output = `cat $simul_file`);
}

sub get_fru{
    my @frucmd = @{(shift)};
    my $verbosity = shift;
    my $fru;
    if(-e '/usr/sbin/ipmi-fru'){
        $fru = '/usr/sbin/ipmi-fru';
    }
    else{
        chomp($fru = `which ipmi-fru`);
    }
    #if sudo is used the command is the second element
    if($frucmd[0] eq 'sudo'){
        $frucmd[1] = $fru;
    }
    else{
        $frucmd[0] = $fru;
    }
    #skip checksum validation
    push @frucmd,'-s';
    my $fruoutput;
    my $returncode;
    run \@frucmd, '>&', \$fruoutput;
    #the upper eight bits contain the error condition (exit code)
    #see http://perldoc.perl.org/perlvar.html#Error-Variables
    $returncode = $? >> 8;
    if ( $returncode != 0 ){
        print "$fruoutput\n";
        print "-> Execution of $fru failed with return code $returncode.\n";
        print "-> $fru was executed with the following parameters:\n";
        print "   ", join(' ', @frucmd), "\n";
        exit(3);
    }
    if($verbosity == 3){
        print "------------- debug output for fru (-vvv is set): ------------\n";
        print "  $fru was executed with the following parameters:\n";
        print "    ", join(' ', @frucmd), "\n";
        print "  output of FreeIPMI:\n";
        print "$fruoutput";
    }
    return split('\n', $fruoutput);
}

sub get_sel{
    my @selcmd = @{(shift)};
    my $verbosity = shift;
    my $sel;
    if(-e '/usr/sbin/ipmi-sel'){
        $sel = '/usr/sbin/ipmi-sel';
    }
    else{
        chomp($sel = `which ipmi-sel`);
    }
    #if sudo is used the command is the second element
    if($selcmd[0] eq 'sudo'){
        $selcmd[1] = $sel;
    }
    else{
        $selcmd[0] = $sel;
    }
    push @selcmd, '--output-event-state', '--interpret-oem-data', '--entity-sensor-names';
    my $seloutput;
    my $returncode;
    run \@selcmd, '>&', \$seloutput;
    $returncode = $? >> 8;
    if ( $returncode != 0 ){
        print "$seloutput\n";
        print "-> Execution of $sel failed with return code $returncode.\n";
        print "-> $sel was executed with the following parameters:\n";
        print "   ", join(' ', @selcmd), "\n";
        exit(3);
    }
    if($verbosity == 3){
        print "------------- debug output for sel (-vvv is set): ------------\n";
        print "  $sel was executed with the following parameters:\n";
        print "    ", join(' ', @selcmd), "\n";
        print "  output of FreeIPMI:\n";
        print "$seloutput";
    }
    return split('\n', $seloutput);
}

sub parse_sel{
    my $selcmd = shift;
    my $verbosity = shift;
    my $sel_xfile = shift;
    my @seloutput = get_sel($selcmd, $verbosity);
    @seloutput = map { [ map { s/^\s*//; s/\s*$//; $_; } split(m/\|/, $_) ] } @seloutput;
    my $header = shift(@seloutput);

    my @sel_rows;
    foreach my $row (@seloutput){
        my %curr_row;
        for(my $i = 0; $i < scalar(@{$header}); $i++){
            my $key = lc $header->[$i];
            $curr_row{$key} = $row->[$i];
        }
        if(!(exclude_with_file($sel_xfile, $curr_row{'name'}, $curr_row{'type'}))){
            push @sel_rows, \%curr_row;
        }
    }
    return \@sel_rows;
}

# Excludes a name and type pair if it is present in the given file, pipe
# delimitered.
# @return 1 if name should be skipped, 0 if not
sub exclude_with_file{
    my $file_name = shift;
    my $name = shift;
    my $type = shift;
    my @xlist;
    my $skip = 0;
    if($file_name){
        if(!(open (FH, "< $file_name"))){
            print "-> Reading exclude file $file_name failed with: $!.\n";
            exit(3);
        };
        @xlist = <FH>;
    }
    foreach my $exclude (@xlist){
        my @curr_exclude = map { s/^\s*//; s/\s*$//; $_; } split(/\|/,$exclude);
        if($curr_exclude[0] eq $name &&
            $curr_exclude[1] eq $type){
            $skip = 1;
        }
    }
    close FH;
    return $skip;
}

#define entire hashes
our %hdrmap = (
    'Record_ID'		=> 'id',	# FreeIPMI ...,0.7.x
    'Record ID'		=> 'id',	# FreeIPMI 0.8.x,... with --legacy-output
    'ID'			=> 'id',	# FreeIPMI 0.8.x
    'Sensor Name'		=> 'name',
    'Name'			=> 'name',	# FreeIPMI 0.8.x
    'Sensor Group'		=> 'type',
    'Type'			=> 'type',	# FreeIPMI 0.8.x
    'Monitoring Status'	=> 'state',
    'State'			=> 'state',	# FreeIPMI 0.8.x
    'Sensor Units'		=> 'units',
    'Units'			=> 'units',	# FreeIPMI 0.8.x
    'Sensor Reading'	=> 'reading',
    'Reading'		=> 'reading',	# FreeIPMI 0.8.x
    'Event'			=> 'event',	# FreeIPMI 0.8.x
    'Lower C'		=> 'lowerC',
    'Lower NC'		=> 'lowerNC',
    'Upper C'		=> 'upperC',
    'Upper NC'		=> 'upperNC',
    'Lower NR'		=> 'lowerNR',
    'Upper NR'		=> 'upperNR',
);

our $verbosity = 0;

MAIN: {
    $| = 1; #force a flush after every write or print
    my @ARGV_SAVE = @ARGV;#keep args for verbose output
    my ($show_help, $show_version);
    my ($ipmi_host, $ipmi_user, $ipmi_password, $ipmi_privilege_level, $ipmi_config_file, $ipmi_outformat);
    my (@freeipmi_options, $freeipmi_compat);
    my (@ipmi_sensor_types, @ipmi_xlist, @ipmi_ilist);
    my (@ipmi_version);
    my $ipmi_sensors = 0;#states to use ipmi-sensors instead of ipmimonitoring
    my $fan_count;#number of fans that should be installed in unit
    my $lanVersion;#if desired use a different protocol version
    my $abort_text = '';
    my $zenoss = 0;
    my $simulate = '';
    my ($use_fru, $no_sel, $no_sudo, $use_thresholds, $no_thresholds, $sel_xfile, $s_xfile);

    #read in command line arguments and init hash variables with the given values from argv
    if ( !( GetOptions(
        'H|host=s'			=> \$ipmi_host,
        'f|config-file=s'	=> \$ipmi_config_file,
        'U|user=s'			=> \$ipmi_user,
        'P|password=s'  	=> \$ipmi_password,
        'L|privilege-level=s'	=> \$ipmi_privilege_level,
        'O|options=s'		=> \@freeipmi_options,
        'b|compat'			=> \$freeipmi_compat,
        'T|sensor-types=s'	=> \@ipmi_sensor_types,
        'fru'				=> \$use_fru,
        'nosel'				=> \$no_sel,
        'nosudo'			=> \$no_sudo,
        'nothresholds'			=> \$no_thresholds,
        'v|verbosity'		=> \$verbosity,
        'vv'				=> sub{$verbosity=2},
        'vvv'				=> sub{$verbosity=3},
        'x|exclude=s'		=> \@ipmi_xlist,
        'sx|selexclude=s'	=> \$sel_xfile,
        'xx|sexclude=s'		=> \$s_xfile,
        'i|include=s'		=> \@ipmi_ilist,
        'o|outformat=s'		=> \$ipmi_outformat,
        'fc|fancount=i'		=> \$fan_count,
        'D=s'				=> \$lanVersion,
        's=s'				=> \$simulate,
        'h|help'			=>
            sub{print STDOUT get_version();
                print STDOUT "\n";
                print STDOUT get_usage();
                print STDOUT "\n";
                print STDOUT get_help();
                exit(0)
            },
        'V|version'			=>
            sub{
                print STDOUT get_version();
                exit(0);
            },
        'usage|?'			=>
            sub{print STDOUT get_usage();
                exit(3);
            }
    ) ) ){
        usage(1);#call usage if GetOptions failed
    }
    usage(1) if @ARGV;#print usage if unknown arg list is left

    ################################################################################
    # check for ipmimonitoring or ipmi-sensors. Since version > 0.8 ipmi-sensors is used
    # if '--legacy-output' is given ipmi-sensors cannot be used
    if( $MISSING_COMMAND_TEXT ne "" ){
        print STDOUT "Error:$MISSING_COMMAND_TEXT";
        exit(3);
    }
    else{
        @ipmi_version = get_ipmi_version();
        if( $ipmi_version[0] > 0 && (grep(/legacy\-output/,@freeipmi_options)) == 0){
            $IPMICOMMAND =~ s/ipmimonitoring/ipmi-sensors/;
            $ipmi_sensors = 1;
        }
        if( $ipmi_version[0] > 0 && (grep(/legacy\-output/,@freeipmi_options)) == 1){
            print "Error: Cannot use ipmi-sensors with option \'--legacy-output\'. Remove it to work correctly.\n";
            exit(3);
        }
        # check if output-sensor-thresholds can be used, this is supported
        # since 1.2.1. Version 1.2.0 was not released, so skip the third minor
        # version number
        if($ipmi_version[0] > 1 || ($ipmi_version[0] == 1 && $ipmi_version[1] >= 2)){
            $use_thresholds = 1;
        }
        else{
            $use_thresholds = 0;
        }
    }
    ###############################################################################
    # verify if all mandatory parameters are set and initialize various variables
    #\s defines any whitespace characters
    #first join the list, then split it at whitespace ' '
    #also cf. http://perldoc.perl.org/Getopt/Long.html#Options-with-multiple-values
    @freeipmi_options = split(/\s+/, join(' ', @freeipmi_options)); # a bit hack, shell word splitting should be implemented...
    @ipmi_sensor_types = split(/,/, join(',', @ipmi_sensor_types));
    @ipmi_xlist = split(/,/, join(',', @ipmi_xlist));
    @ipmi_ilist = split(/,/, join(',', @ipmi_ilist));

    #check for zenoss output
    if(defined $ipmi_outformat && $ipmi_outformat eq "zenoss"){
        $zenoss = 1;
    }

    # Define basic ipmi command
    my @basecmd = $IPMICOMMAND;
    # If host is omitted localhost is assumed, if not turned off sudo is used
    if(!(defined $ipmi_host) || ($ipmi_host eq 'localhost')){
        if(!defined($no_sudo)){
            # Only add sudo if not already root
            @basecmd = ($> != 0 ? 'sudo' : (), $IPMICOMMAND);
        }
    }
    # If we are not local, we need authentication credentials
    else{
        # Add the ipmi desired host
        push @basecmd, '-h', $ipmi_host;
        if(defined $ipmi_config_file){
            push @basecmd, '--config-file', $ipmi_config_file;
        }
        elsif(defined $ipmi_user && defined $ipmi_password && defined $ipmi_privilege_level ){
            push @basecmd, '-u', $ipmi_user, '-p', $ipmi_password, '-l', $ipmi_privilege_level;
        }
        else{
            $abort_text = $abort_text . " -f <FreeIPMI config file> or -U <username> -P <password> -L <privilege level>";
        }
        if( $abort_text ne ""){
            print STDOUT "Error: " . $abort_text . " missing.";
            print STDOUT get_usage();
            exit(3);
        }
    }
    # copy command for fru usage
    my @frucmd;
    if($use_fru){
        @frucmd = @basecmd
    }
    my @selcmd = @basecmd;

    # , is the seperator in the new string
    if(@ipmi_sensor_types){
        push @basecmd, '-g', join(',', @ipmi_sensor_types);
    }
    if(@freeipmi_options){
        push @basecmd, @freeipmi_options;
    }

    #keep original basecmd for later usage
    my @getstatus = @basecmd;

    #if -b is not defined, caching options are used
    if( !(defined $freeipmi_compat) ){
        push @getstatus, '--quiet-cache', '--sdr-cache-recreate';
    }
    #since version 0.8 it is possible to interpret OEM data
    if( ($ipmi_version[0] == 0 && $ipmi_version[1] > 7) ||
        $ipmi_version[0] > 0){
        push @getstatus, '--interpret-oem-data';
    }
    #since version 0.8 it is necessary to add the legacy option
    if( ($ipmi_version[0] == 0 && $ipmi_version[1] > 7) && (grep(/legacy\-output/,@freeipmi_options) == 0)){
        push @getstatus, '--legacy-output';
    }
    #if ipmi-sensors is used show the state of sensors and ignore N/A
    if($ipmi_sensors){
        push @getstatus, '--output-sensor-state', '--ignore-not-available-sensors';
    }
    #if not stated otherwise we use protocol lan version 2 per default
    if(!defined($lanVersion)){
        $lanVersion = 'LAN_2_0';
    }
    if($lanVersion ne 'default' && defined $ipmi_host && $ipmi_host ne 'localhost'){
        push @getstatus, "--driver-type=$lanVersion";
        if(!$no_sel){
            push @selcmd, "--driver-type=$lanVersion";
        }
        if($use_fru){
            push @frucmd, "--driver-type=$lanVersion";
        }
    }
    if($use_thresholds && !$no_thresholds){
        push @getstatus, '--output-sensor-thresholds';
    }

    ################################################################################
    #execute status command and redirect stdout and stderr to ipmioutput
    my $ipmioutput;
    my $returncode;
    if(!$simulate){
        run \@getstatus, '>&', \$ipmioutput;
        #the upper eight bits contain the error condition (exit code)
        #see http://perldoc.perl.org/perlvar.html#Error-Variables
        $returncode = $? >> 8;
    }
    else{
        $ipmioutput = simulate($simulate);
        print "DEBUG: Using simulation mode\n";
        $returncode = 0;
    }
    my @fruoutput;
    if($use_fru){
        @fruoutput = get_fru(\@frucmd, $verbosity);
    }
    my $seloutput;
    if(!$no_sel){
        $seloutput = parse_sel(\@selcmd, $verbosity, $sel_xfile);
    }
    ################################################################################
    # print debug output when verbosity is set to 3 (-vvv)
    if ( $verbosity == 3 ){
        my $ipmicommandversion;
        run [$IPMICOMMAND, '-V'], '2>&1', '|', ['head', '-n', 1], '&>', \$ipmicommandversion;
        #remove trailing newline with chomp
        chomp $ipmicommandversion;
        print "------------- debug output for sensors (-vvv is set): ------------\n";
        print "  script was executed with the following parameters:\n";
        print "    $0 ", join(' ', @ARGV_SAVE), "\n";
        print "  check_ipmi_sensor version:\n";
        print "    $check_ipmi_sensor_version\n";
        print "  FreeIPMI version:\n";
        print "    $ipmicommandversion\n";
        print "  FreeIPMI was executed with the following parameters:\n";
        print "    ", join(' ', @getstatus), "\n";
        print "  FreeIPMI return code: $returncode\n";
        print "  output of FreeIPMI:\n";
        print "$ipmioutput\n";
        print "--------------------- end of debug output ---------------------\n";
    }

    ################################################################################
    # generate main output
    if ( $returncode != 0 ){
        print "$ipmioutput\n";
        print "-> Execution of $IPMICOMMAND failed with return code $returncode.\n";
        print "-> $IPMICOMMAND was executed with the following parameters:\n";
        print "   ", join(' ', @getstatus), "\n";
        exit(3);
    }
    else{
        my @outputRows;
        if(defined($ipmioutput)){
            @outputRows = split('\n', $ipmioutput);
        }
        if(!defined($ipmioutput) || scalar(@outputRows) == 1){
            print "-> Execution of FreeIPMI returned an empty output or only 1 header row!\n";
            print "-> $IPMICOMMAND was executed with the following parameters:\n";
            print "   ", join(' ', @getstatus), "\n";
            exit(3);
        }
        #print desired filter types
        if ( @ipmi_sensor_types ){
            print "Sensor Type(s) ", join(', ', @ipmi_sensor_types), " Status: ";
        }
        else{
            print "IPMI Status: ";
        }
        #split at newlines, fetch array with lines of output
        my @ipmioutput = split('\n', $ipmioutput);

        #remove sudo errors and warnings like they appear on dns resolving issues
        @ipmioutput = map { /^sudo:/ ? () : $_ } @ipmioutput;

        #remove leading and trailing whitespace characters, split at the pipe delimiter
        @ipmioutput = map { [ map { s/^\s*//; s/\s*$//; $_; } split(m/\|/, $_) ] } @ipmioutput;

        #shift out the header as it is the first line
        my $header = shift @ipmioutput;
        if(!defined($header)){
            print "$ipmioutput\n";
            print " FreeIPMI returned an empty header map (first line)";
            if(@ipmi_sensor_types){
                print " FreeIPMI could not find any sensors for the given sensor type (option '-T').\n";
            }
            exit(3);
        }
        my %header;
        for(my $i = 0; $i < @$header; $i++)
        {
            #assigning %header with (key from hdrmap) => $i
            #checking at which position in the header is which key
            $header{$hdrmap{$header->[$i]}} = $i;
        }
        my @ipmioutput2;
        foreach my $row ( @ipmioutput ){
            my %row;
            #fetch keys from header and assign existent values to row
            #this maps the values from row(ipmioutput) to the header values
            while ( my ($key, $index) = each %header ){
                $row{$key} = $row->[$index];
            }
            if(!(exclude_with_file($s_xfile, $row{'name'}, $row{'type'}))){
                push @ipmioutput2, \%row;
            }
        }
        #create hash with sensor name an 1
        my %ipmi_xlist = map { ($_, 1) } @ipmi_xlist;
        #filter out the desired sensor values
        @ipmioutput2 = grep(!exists $ipmi_xlist{$_->{'id'}}, @ipmioutput2);
        #check for an include list
        if(@ipmi_ilist){
            my %ipmi_ilist = map { ($_, 1) } @ipmi_ilist;
            #only include sensors from include list
            @ipmioutput2 = grep(exists $ipmi_ilist{$_->{'id'}}, @ipmioutput2);
        }
        #start with main output
        my $exit = 0;
        my $w_sensors = '';#sensors with warnings
        my $perf = '';#performance sensor
        my $curr_fans = 0;
        foreach my $row ( @ipmioutput2 ){
            if( $zenoss ){
                $row->{'name'} =~ s/ /_/g;
            }
            #check for warning sensors
            if ( $row->{'state'} ne 'Nominal' && $row->{'state'} ne 'N/A' ){
                $exit = 1 if $exit < 1;
                $exit = 2 if $exit < 2 && $row->{'state'} ne 'Warning';
                #don't insert a , the first time
                $w_sensors .= ", " unless $w_sensors eq '';
                $w_sensors .= "$row->{'name'} = $row->{'state'}";
                if( $verbosity ){
                    if( $row->{'reading'} ne 'N/A'){
                        $w_sensors .= " ($row->{'reading'})" ;
                    }
                    else{
                        $w_sensors .= " ($row->{'event'})";
                    }
                }
            }
            if ( $row->{'units'} ne 'N/A' ){
                my $val = $row->{'reading'};
                my $perf_data;
                my $perf_thresholds;
                if($zenoss){
                    $perf_data = $row->{'name'}."=".$val;
                }
                else{
                    $perf_data = "'".$row->{'name'}."'=".$val;
                }
                if($use_thresholds && !$no_thresholds){
                    if(($row->{'lowerNC'} ne 'N/A') && ($row->{'upperNC'} ne 'N/A')){
                        $perf_thresholds = $row->{'lowerNC'}.":".$row->{'upperNC'}.";";
                    }
                    elsif(($row->{'lowerNC'} ne 'N/A') && ($row->{'upperNC'} eq 'N/A')){
                        $perf_thresholds = $row->{'lowerNC'}.":;";
                    }
                    elsif(($row->{'lowerNC'} eq 'N/A') && ($row->{'upperNC'} ne 'N/A')){
                        $perf_thresholds = "~:".$row->{'upperNC'}.";";
                    }
                    elsif(($row->{'lowerNC'} eq 'N/A') && ($row->{'upperNC'} eq 'N/A')){
                        $perf_thresholds = ";";
                    }
                    if(($row->{'lowerC'} ne 'N/A') && ($row->{'upperC'} ne 'N/A')){
                        $perf_thresholds .= $row->{'lowerC'}.":".$row->{'upperC'};
                    }
                    elsif(($row->{'lowerC'} ne 'N/A') && ($row->{'upperC'} eq 'N/A')){
                        $perf_thresholds .= $row->{'lowerC'}.":";
                    }
                    elsif(($row->{'lowerC'} eq 'N/A') && ($row->{'upperC'} ne 'N/A')){
                        $perf_thresholds .= "~:".$row->{'upperC'};
                    }
                    # Add thresholds to performance data
                    if(($row->{'lowerNC'} ne 'N/A') || ($row->{'upperNC'} ne 'N/A') ||
                        ($row->{'lowerC'} ne 'N/A') || ($row->{'upperC'} ne 'N/A')){
                        $perf_data .= ";".$perf_thresholds;
                    }
                }
                $perf .= $perf_data." ";
            }
            if( $row->{'type'} eq 'Fan' && $row->{'reading'} ne 'N/A' ){
                $curr_fans++;
            }
        }
        foreach my $row (@{$seloutput}){
            if( $zenoss ){
                $row->{'name'} =~ s/ /_/g;
            }
            if ($row->{'state'} ne 'Nominal'){
                $exit = 1 if $exit < 1;
                $exit = 2 if $exit < 2 && $row->{'state'} ne 'Warning';
                $w_sensors .= ", " unless $w_sensors eq '';
                $w_sensors .= "$row->{'name'} = $row->{'state'}";
                if( $verbosity ){
                    if(defined($row->{'type'})){
                        $w_sensors .= " ($row->{'type'})" ;
                    }
                }
            }
        }
        #now check if num fans equals desired unit fans
        if( $fan_count ){
            if( $curr_fans < $fan_count ){
                $exit = 1 if $exit < 1;
                $w_sensors .= ", " unless $w_sensors eq '';
                $w_sensors .= "Fan = Warning";
                if( $verbosity ){
                    $w_sensors .= " ($curr_fans)" ;
                }
            }
        }
        #check for the FRU serial number
        my @server_serial;
        my $serial_number;
        if( $use_fru ){
            @server_serial = grep(/Product Serial Number/,@fruoutput);
            if(@server_serial){
                $server_serial[0] =~ m/(\d+)/;
                $serial_number = $1;
            }
        }
        $perf = substr($perf, 0, -1);#cut off the last chars
        if ( $exit == 0 ){
            print "OK";
        }
        elsif ( $exit == 1 ){
            print "Warning [$w_sensors]";
        }
        else{
            print "Critical [$w_sensors]";
        }
        if( $use_fru && defined($serial_number)){
            print " ($serial_number)";
        }
        print " | ", $perf if $perf ne '';
        print "\n";

        if ( $verbosity > 1 ){
            foreach my $row (@ipmioutput2){
                if( $row->{'state'} eq 'N/A'){
                    next;
                }
                elsif( $row->{'reading'} ne 'N/A'){
                    print "$row->{'name'} = $row->{'reading'} ";
                }
                elsif( $row->{'event'} ne 'N/A'){
                    print "$row->{'name'} = $row->{'event'} ";
                }
                else{
                    next;
                }
                print "(Status: $row->{'state'})\n";
            }
        }
        exit $exit;
    }
};

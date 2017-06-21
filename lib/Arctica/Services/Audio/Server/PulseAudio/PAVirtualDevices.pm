################################################################################
#          _____ _
#         |_   _| |_  ___
#           | | | ' \/ -_)
#           |_| |_||_\___|
#                   _   _             ____            _           _
#    / \   _ __ ___| |_(_) ___ __ _  |  _ \ _ __ ___ (_) ___  ___| |_
#   / _ \ | '__/ __| __| |/ __/ _` | | |_) | '__/ _ \| |/ _ \/ __| __|
#  / ___ \| | | (__| |_| | (_| (_| | |  __/| | | (_) | |  __/ (__| |_
# /_/   \_\_|  \___|\__|_|\___\__,_| |_|   |_|  \___// |\___|\___|\__|
#                                                  |__/
#          The Arctica Modular Remote Computing Framework
#
################################################################################
#
# Copyright (C) 2015-2016 The Arctica Project
# http://arctica-project.org/
#
# This code is dual licensed: strictly GPL-2 or AGPL-3+
#
# GPL-2
# -----
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the
# Free Software Foundation, Inc.,
#
# 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA.
#
# AGPL-3+
# -------
# This programm is free software; you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This programm is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program; if not, write to the
# Free Software Foundation, Inc.,
# 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA.
#
# Copyright (C) 2015-2017 Guangzhou Nianguan Electronics Technology Co.Ltd.
#                         <opensource@gznianguan.com>
# Copyright (C) 2015-2017 Mike Gabriel <mike.gabriel@das-netzwerkteam.de>
#
################################################################################
package Arctica::Services::Audio::Server::PulseAudio::PAVirtualDevices;
use strict;
use Exporter qw(import);
use Arctica::Core::BugOUT::Basics qw( BugOUT );
use Arctica::Core::Mother::Forker;
use Data::Dumper;# Remove this before release! (unless we're still dependant)

# Be very selective about what (if any) gets exported by default:
our @EXPORT = qw( );
# And be mindfull of what we lett the caller request here too:
our @EXPORT_OK = qw( getLIST_amap_by_name );

my $arctica_core_object;

sub new {
	BugOUT(9,"PAVirtualDevices new->ENTER");
	my $class_name = $_[0];# Be EXPLICIT!! DON'T SHIFT OR "@_";
	$arctica_core_object = $_[1];
	my $self = {
		isArctica => 1, # Declare that this is a Arctica "something"
		aobject_name => "PulseAudio_Devices",
		hook_device_state => $_[2]->{'hook_device_state'},
		pa_timeout => 5,
	};


	bless($self, $class_name);
# Set up initial "required" default devices... (Do this cleaner in the future!?)
# At some point we may add support for dynamically creating new devices.
	$self->{'pa_vdev'}{'input'}{0}{'pa_sink_name'} = "arctica.input0";
	$self->{'pa_vdev'}{'input'}{0}{'pa_source_name'} = "arctica.mic0";
	$self->{'pa_vdev'}{'input'}{0}{'pa_state'} = "S";
	$self->{'pa_vdev'}{'input'}{0}{'pa_idle_since'} = 0;
	$self->{'pa_vdev'}{'input'}{0}{'our_state'} = "S";
	$self->{'pa_vdev'}{'input'}{0}{'gst_thread'} = 0;
	$self->{'pa_vdev'}{'output'}{0}{'pa_sink_name'} = "arctica.output0";
	$self->{'pa_vdev'}{'output'}{0}{'pa_state'} = "S";
	$self->{'pa_vdev'}{'output'}{0}{'pa_idle_since'} = 0;
	$self->{'pa_vdev'}{'output'}{0}{'our_state'} = "S";
	$self->{'pa_vdev'}{'output'}{0}{'gst_thread'} = 0;

# "action_map" may go away.... (limited usefullness if any in current itteration of code.)
	$self->{'pa_vdev'}{'action_map'}{'by_name'}{'arctica.mic0'} =
							{
								type  => "input",
								idnum => 0,
							};
	$self->{'pa_vdev'}{'action_map'}{'by_name'}{'arctica.output0'} =
							{
								type  => "output",
								idnum => 0,
							};
# Start Subscribing to PA Events
# FIXME Structure of output from pactl is not guaranteed to be reliable but works ok for now.
# Replace with custom PA client in the future.
	$self->{'subscribe_pulse_events'} = Arctica::Core::Mother::Forker->new($arctica_core_object,{# FIXME Clean up this one!
		child_name	=>	'pulse_events',
		fork_style	=>	'interactive_pty',
		handle_stdeoc	=>	sub {$self->_pulse_event_handler(@_)},
		return_stdin	=>	0,
		exec_hold	=>	0,
		env_strict	=>	0,
		env_pass	=> {
			'ARCTICA'	=> 1,
			'USER'		=> 1,
		},
		exec_path	=>	"/usr/bin/pactl",# FIXME  Make this configurable!
		exec_cl_argv	=>	["subscribe"],

	});

	$arctica_core_object->{'aobj'}{'AudioServer'}{'PA_Virtual_Devices'} = \$self;

	$self->{'GlibTimeout_suspend_idle'} = Glib::Timeout->add (1000, sub {$self->_suspend_idle}, undef, 1 );

	BugOUT(9,"PAVirtualDevices new->DONE");

	return $self;
}


sub _suspend_idle {# Cause we can't always rely on PulseAudio for this.... (PA BUG?)
	my $self = $_[0];
	foreach my $idnum (keys %{$self->{'pa_vdev'}{'input'}}) {
		if (($self->{'pa_vdev'}{'input'}{$idnum}{'pa_state'} eq "I") and ($self->{'pa_vdev'}{'input'}{$idnum}{'our_state'} ne "S")) {
			if ($self->{'pa_vdev'}{'input'}{$idnum}{'pa_idle_since'} < (time - $self->{'pa_timeout'})) {
				$self->_set_device_our_state("input",$idnum,$self->{'pa_vdev'}{'input'}{$idnum}{'pa_source_name'},"S");
			}

		}
	}

	foreach my $idnum (keys %{$self->{'pa_vdev'}{'output'}}) {
		if (($self->{'pa_vdev'}{'output'}{$idnum}{'pa_state'} eq "I") and ($self->{'pa_vdev'}{'output'}{$idnum}{'our_state'} ne "S")) {
			if ($self->{'pa_vdev'}{'output'}{$idnum}{'pa_idle_since'} < (time - $self->{'pa_timeout'})) {
				$self->_set_device_our_state("output",$idnum,$self->{'pa_vdev'}{'output'}{$idnum}{'pa_sink_name'},"S");
			}

		}
	}
	return 1;
}

sub _set_device_our_state {
	BugOUT(9,"set_device_our_state ENTER");
	my $self = $_[0];
	my $type = $_[1];
	my $idnum = $_[2];
	my $name = $_[3];
	my $new_state = $_[4];

	if ($type eq "input") {
		BugOUT(8,"INPUT");
		if ($self->{'pa_vdev'}{'input'}{$idnum}{'pa_source_name'} eq $name) {# overkill but sanity checks can be good...

			unless ($self->{'pa_vdev'}{'input'}{$idnum}{'our_state'} eq $new_state) {
				$self->{'pa_vdev'}{'input'}{$idnum}{'our_state'} = $new_state;
#print "$name\t$new_state\n";
#				if ($new_state eq "R") {
#				} elsif ($new_state eq "I") {
#				} elsif ($new_state eq "S") {
#				}
				$self->{'hook_device_state'}($type,$idnum,$name,$new_state);
			} else {
					# DO NOTHING !
			}

		}

	} elsif ($type eq "output") {
		BugOUT(8,"OUTPUT");
		if ($self->{'pa_vdev'}{'output'}{$idnum}{'pa_sink_name'} eq $name) {

			unless ($self->{'pa_vdev'}{'output'}{$idnum}{'our_state'} eq $new_state) {
				$self->{'pa_vdev'}{'output'}{$idnum}{'our_state'} = $new_state;
#print "$name\t$new_state\n";
#				if ($new_state eq "R") {
#				} elsif ($new_state eq "I") {
#				} elsif ($new_state eq "S") {
#				}
				$self->{'hook_device_state'}($type,$idnum,$name,$new_state);
			}

		}


	}


	BugOUT(9,"set_device_our_state DONE");
}

sub _set_device_pa_state {
	BugOUT(9,"set_device_pa_state ENTER");
	my $self = $_[0];
	my $type = $_[1];
	my $idnum = $_[2];
	my $name = $_[3];
	my $new_state = $_[4];

	if ($type eq "input") {
#		BugOUT(8,"INPUT");
		if ($self->{'pa_vdev'}{'input'}{$idnum}{'pa_source_name'} eq $name) {# overkill but sanity checks can be good...

			unless ($self->{'pa_vdev'}{'input'}{$idnum}{'pa_state'} eq $new_state) {
				$self->{'pa_vdev'}{'input'}{$idnum}{'pa_state'} = $new_state;

				if ($new_state eq "R") {
					$self->{'pa_vdev'}{'input'}{$idnum}{'pa_idle_since'} = 0;
					$self->_set_device_our_state($type,$idnum,$name,$new_state);

				} elsif ($new_state eq "I") {
					$self->{'pa_vdev'}{'input'}{$idnum}{'pa_idle_since'} = time();
#					$self->_set_device_our_state($type,$idnum,$name,$new_state);

				} elsif ($new_state eq "S") {
					$self->_set_device_our_state($type,$idnum,$name,$new_state);

				}

			} else {
				# DO NOTHING?
			}

		}

	} elsif ($type eq "output") {
#		BugOUT(8,"OUTPUT");
		if ($self->{'pa_vdev'}{'output'}{$idnum}{'pa_sink_name'} eq $name) {

			unless ($self->{'pa_vdev'}{'output'}{$idnum}{'pa_state'} eq $new_state) {
				$self->{'pa_vdev'}{'output'}{$idnum}{'pa_state'} = $new_state;
#print "$name\t$new_state\n";
				if ($new_state eq "R") {
					$self->{'pa_vdev'}{'output'}{$idnum}{'pa_idle_since'} = 0;
					$self->_set_device_our_state($type,$idnum,$name,$new_state);

				} elsif ($new_state eq "I") {
					$self->{'pa_vdev'}{'output'}{$idnum}{'pa_idle_since'} = time();
#					$self->_set_device_our_state($type,$idnum,$name,$new_state);

				} elsif ($new_state eq "S") {
					$self->_set_device_our_state($type,$idnum,$name,$new_state);

				}

			} else {
				# DO NOTHING?
			}

		}


	}
	BugOUT(9,"set_device_pa_state DONE");

}

sub _pulse_event_handler {
	BugOUT(9,"_pulse_event_handler: ENTER");
	my $self = $_[0];
	if ($_[1] =~ /Event\s*\'change\'\s*on\s*(\w{4,6})\s/) {
		my $chWhere = $1;
		if (($chWhere eq "source") or ($chWhere eq "sink")) {
#			BugOUT(9,"_pulse_event_handler: device is $chWhere");
			my $devices = $self->get_list('action_map','by_name');
			open(PACTL, "-|", "/usr/bin/pactl","list","$chWhere"."s","short");# FIXME Use mother:forker::light  when its ready!?
			while (<PACTL>) {
				if ($_ =~ /.*\s*(arctica\.[^\s]*)(.*)\n/) {
					my $name = $1;
					if ($devices->{$name}) {
						if ($2=~ /(IDLE)$/) {
							$self->_set_device_pa_state($devices->{$name}{'type'},$devices->{$name}{'idnum'},$name,"I");
						} elsif ($2 =~ /(SUSPENDED)$/) {
							$self->_set_device_pa_state($devices->{$name}{'type'},$devices->{$name}{'idnum'},$name,"S");
						} elsif ($2 =~ /(RUNNING)$/) {
							$self->_set_device_pa_state($devices->{$name}{'type'},$devices->{$name}{'idnum'},$name,"R");
						}
					}
				}
			}
			close(PACTL);
		} else {
			BugOUT(9,"pulse_event_handler: event we currently don't care about... (Yawn..)");
		}

	}
	BugOUT(9,"_pulse_event_handler: DONE");
	return 1;
}

sub force_chk_dev_state {
	BugOUT(8,"USE OF/(THE?) FORCE!!!: ENTER");
	my $self = $_[0];
# (W)HACKY BUT WORKS FINE FOR NOW
	$self->_pulse_event_handler("Event 'change' on source ");
	$self->_pulse_event_handler("Event 'change' on sink ");
	BugOUT(8,"THE LAST JEDI RETIRES...");
}

sub get_list {
	BugOUT(8,"PAVirtualDevices getLIST");
	my $self = $_[0];
	if ($_[1] eq 'action_map') {
		if ($_[2] eq 'by_name') {
			return $self->{'pa_vdev'}{'action_map'}{'by_name'};
		}
	}
}

1;



# ---------- Track -----------
use strict;
package Audio::Ecasound::Multitrack::Track;
our $VERSION = 1.0;
our ($debug);
local $debug = 0;
#use Exporter qw(import);
#our @EXPORT_OK = qw(track);
use Audio::Ecasound::Multitrack::Assign qw(join_path);
use Carp;
use IO::All;
use vars qw($n %by_name @by_index %track_names);
use Audio::Ecasound::Multitrack::Wav;
our @ISA = 'Audio::Ecasound::Multitrack::Wav';
$n = 0; 	# incrementing numeric key
@by_index = ();	# return ref to Track by numeric key
%by_name = ();	# return ref to Track by name

# attributes offset, loop, delay for entire setup
# attribute  modifiers
# new attribute will be 
use Audio::Ecasound::Multitrack::Object qw( 		name
						active

						ch_r 
						ch_m 
						ch_count
						
						rw

						vol  
						pan 
						old_vol_level
						old_pan_level
						ops 
						offset 

						n 
						group 

						
						delay
						start_position
						length
						looping

						hide
						modifiers

						jack_source
						jack_send
						source_select
						send_select
						
						);

# Note that ->vol return the effect_id 
# ->old_volume_level is the level saved before muting
# ->old_pan_level is the level saved before pan full right/left
# commands

sub new {
	# returns a reference to an object that is indexed by
	# name and by an assigned index
	#
	# The indexing is bypassed and an object returned 
	# if an index n is supplied as  a parameter
	
	my $class = shift;
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	#print "test 1\n";
	if ($by_name{$vals{name}}){
	#print "test 2\n";
			my $track = $by_name{$vals{name}};
			# print $track->name, " hide: ", $track->hide, $/;
			if ($track->hide) {
				$track->set(hide => 0);
				return $track;

			} else {
		carp  ("track name already in use: $vals{name}\n"), return
		 if $track_names{$vals{name}}; 

		}
	}
	my $n = $vals{n} ? $vals{n} : ++$n; 
	my $object = bless { 


		## 		defaults ##

					name 	=> "Audio_$n", 
					group	=> 'Tracker', 
					rw   	=> 'REC', 
					n    	=> $n,
					ops     => [],
					active	=> undef,
					ch_r 	=> undef,
					ch_m 	=> undef,
					ch_count => 1,
					vol  	=> undef,
					pan 	=> undef,

					modifiers => q(), # start, reverse, audioloop, playat

					
					delay	=> undef, # after how long we start playback
					                  # the term 'offset' is used already
					start_position => undef, # where we start playback from
					length => undef, # how long we play back
					looping => undef, # do we repeat our sound sample

					hide     => undef, # for 'Remove Track' function
					source_select => q(soundcard),
					send_select => undef,

					@_ 			}, $class;

	#print "object class: $class, object type: ", ref $object, $/;
	$track_names{$vals{name}}++;
	#print "names used: ", Audio::Ecasound::Multitrack::yaml_out( \%track_names );
	$by_index[$n] = $object;
	$by_name{ $object->name } = $object;
	
	Audio::Ecasound::Multitrack::add_volume_control($n);
	Audio::Ecasound::Multitrack::add_pan_control($n);

	#my $group = $Audio::Ecasound::Multitrack::Group::by_name{ $object->group }; 

	# create group if necessary
	#defined $group or $group = Audio::Ecasound::Multitrack::Group->new( name => $object->group );
	#my @existing = $group->tracks ;
	#$group->set( tracks => [ @existing, $object->name ]);
	$Audio::Ecasound::Multitrack::this_track = $object;
	$object;
	
}


sub dir { Audio::Ecasound::Multitrack::this_wav_dir() } # replaces dir field

sub full_path { my $track = shift; join_path $track->dir , $track->current }

sub group_last {
	my $track = shift;
	my $group = $Audio::Ecasound::Multitrack::Group::by_name{$track->group}; 
	#print join " ", 'searching tracks:', $group->tracks, $/;
	my $max = 0;
	map{ 
		my $track = $_;
		my $last;
		$last = $track->last ? $track->last : 0;
		#print "track: ", $track->name, ", last: $last\n";

		$max = $last if $last > $max;

	}	map { $by_name{$_} } $group->tracks;
	$max;
}

sub current {	 # depends on ewf status
	my $track = shift;
	my $last = $track->group_last;
	#print "last found is $last\n"; 
	if 	($track->rec_status eq 'REC'){ 
		return $track->name . '_' . ++$last . '.wav'}
	elsif ( $track->rec_status eq 'MON'){ 

	# here comes the logic that enables .ewf support, 
	# using conditional $track->delay or $track->length or $track->start_position ;
	# to decide whether to rewrite file name from .wav to .ewf
	
		no warnings;
		my $filename = $track->targets->{ $track->monitor_version } ;
		use warnings;
		return $filename  # setup directly refers to .wav file
		  unless $track->delay or $track->length or $track->start_position ;

		  # setup uses .ewf parameters, expects .ewf file to
		  # be written

		#filename in chain setup now point to .ewf file instead of .wav
		
		$filename =~ s/\.wav$/.ewf/;
		return $filename;
	} else {
		$debug and print "track ", $track->name, ": no current version\n" ;
		return undef;
	}
}

sub full_wav_path {  # independent of ewf status
	my $track = shift; 
	join_path $track->dir , $track->current_wav
}

sub current_wav {	# independent of ewf status
	my $track = shift;
	my $last = $track->group_last;
	#print "last found is $last\n"; 
	if 	($track->rec_status eq 'REC'){ 
		return $track->name . '_' . ++$last . '.wav'}
	elsif ( $track->rec_status eq 'MON'){ 
		no warnings;
		my $filename = $track->targets->{ $track->monitor_version } ;
		use warnings;
		return $filename;
	} else {
		# print "track ", $track->name, ": no current version\n" ;
		return undef;
	}
}
sub write_ewf {
	$Audio::Ecasound::Multitrack::debug2 and print "&write_ewf\n";
	my $track = shift;
	my $wav = $track->full_wav_path;
	my $ewf = $wav;
	$ewf =~ s/\.wav$/.ewf/;
	#print "wav: $wav\n";
	#print "ewf: $ewf\n";

	my $maybe_ewf = $track->full_path; 
	$wav eq $maybe_ewf and unlink( $ewf), return; # we're not needed
	$ewf = File::Spec::Link->resolve_all( $ewf );
	carp("no ewf parameters"), return 0 if !( $track->delay or $track->start_position or $track->length);

	my @lines;
	push @lines, join " = ", "source", $track->full_wav_path;
	map{ push @lines, join " = ", $_, eval qq(\$track->$_) }
	grep{ eval qq(\$track->$_)} qw(delay start_position length);
	my $content = join $/, @lines;
	#print $content, $/;
	$content > io($ewf) ;
	return $content;
}

sub current_version {	
	my $track = shift;
	my $last = $track->group_last;
	my $status = $track->rec_status;
	#print "last: $last status: $status\n";
	if 	($track->rec_status eq 'REC'){ return ++$last}
	elsif ( $track->rec_status eq 'MON'){ return $track->monitor_version } 
	else { return undef }
}

sub monitor_version {
	my $track = shift;
	my $group = $Audio::Ecasound::Multitrack::Group::by_name{$track->group};
	my $version; 
	if ( $track->active 
			and grep {$track->active == $_ } @{$track->versions}) 
		{ $version = $track->active }
	elsif (	$group->version
			and grep {$group->version  == $_ } @{$track->versions})
		{ $version = $group->version }
#	elsif (	$track->last) #  and ! $track->active and ! $group->version )
#		{ $version = $track->last }
	else { } # carp "no version to monitor!\n" 
	# print "monitor version: $version\n";
	$version;
}

sub rec_status {
	my $track = shift;
	# print "rec status track: ", $track->name, $/;
	my $group = $Audio::Ecasound::Multitrack::Group::by_name{$track->group};

		
	return 'OFF' if 
		$group->rw eq 'OFF'
		or $track->rw eq 'OFF'
		or $track->rw eq 'MON' and ! $track->monitor_version
		or $track->hide;
		# ! $track->full_path;
		;
	if( 	
		$track->rw eq 'REC'
		 and $group->rw eq 'REC'
		) {

		return 'REC'; # if $track->ch_r;
		#return 'MON' if $track->monitor_version;
		#return 'OFF';
	}
	else { return 'MON' if $track->monitor_version;
			return 'OFF';	
	}
}
# the following methods handle effects
sub remove_effect {
	my $track = shift;
	my @ids = @_;
	$track->set(ops => [ grep { my $existing = $_; 
									! grep { $existing eq $_
									} @ids }  
							@{$track->ops} ]);
}

# the following methods are for channel routing

sub mono_to_stereo { 
	my $track = shift;
	my $cmd = "file " .  $track->full_path;
	if ( 	$track->ch_count == 2
		    or  -e $track->full_path
				and qx(which file)
				and qx($cmd) =~ /stereo/i ){ 
		return "" 
	} elsif ( $track->ch_count == 1 ){
		return " -chcopy:1,2 " 
	} else { carp "Track ".$track->name.": Unexpected channel count\n"; }
}

sub rec_route {
	no warnings qw(uninitialized);
	my $track = shift;
	
	# no need to route a jack client
	return if $track->source_select eq 'jack';

	# no need to route a signal at channel 1
	return if ! $track->ch_r or $track->ch_r == 1; 
	
	my $route = "-chmove:" . $track->ch_r . ",1"; 
	if ( $track->ch_count == 2){
		$route .= " -chmove:" . ($track->ch_r + 1) . ",2";
	}
	return $route;
	
}
sub route {

	# routes signals 1,2,3,...$width to $dest + 0, $dest + 1, $dest + 2,... 
	
	my ($width, $dest) = @_;
	return undef if $dest == 1 or $dest == 0;
	# print "route: width: $width, destination: $dest\n\n";
	my $offset = $dest - 1;
	my $map ;
	for my $c ( map{$width - $_ + 1} 1..$width ) {
		$map .= " -chmove:$c," . ( $c + $offset);
		#$map .= " -eac:0,"  . $c;
	}
	$map;
}

# channel shifting for multi rule 
#
sub pre_send {
	#$debug2 and print "&pre_send\n";
	my $track = shift;

	# we channel shift only to soundcard channel numbers higher than 3,
	# not when the send is to a jack client
	 
	return q() if $track->send_select eq 'jack'  or ! $track->aux_output;           
	route(2,$track->aux_output); # stereo signal
}

# The following subroutine is not an object method.

sub all { @by_index[1..scalar @by_index - 1] }


### Commands and their support functions

sub source { # command for setting, showing track source
	my ($track, $source) = @_;

	if ( ! $source ){
		if ( Audio::Ecasound::Multitrack::jackd_running()
				and $track->jack_source 
				and $track->source_select eq 'jack'){
			$track->jack_source 
		} else { 
			$track->input 
		}
	} elsif ( $source =~ m(\D) ){
		if ( Audio::Ecasound::Multitrack::jackd_running() ){
			$track->set(jack_source => $source);
			$track->set(source_select => "jack");
			$track->jack_source
		} else {
			print "JACK server not running.\n";
			$track->input;
		} 
	} else {  # must be numerical
		$track->set(ch_r => $source);
		$track->set(source_select =>'soundcard');
		$track->input;
	}
} 

sub set_send {
	my ($track, $output) = @_;
	my $old_send = $track->send;
	my $new_send = $track->send($output);
	my $object = $track->output_object;
	if ( $old_send  eq $new_send ){
		print $track->name, ": send unchanged, $object\n";
	} else {
		print $track->name, ": auxiliary output to ",
		($object ? $object : 'off'),
		"\n";
	}
}
sub send {
	my ($track, $send) = @_;

	if ( ! defined $send ){
		if ( Audio::Ecasound::Multitrack::jackd_running()
				and $track->jack_send 
				and $track->send_select eq 'jack'){
			$track->jack_send 
		} else { 
			$track->send_select eq 'soundcard'
				?  $track->aux_output
				:  undef
		}
	} elsif (lc $send eq 'off'  or $send == 0) { 
		$track->set(send_select => 'off');
		undef;
	} elsif ( $send =~ m(\D) ){ ## non-digit, indicating jack client name
		if ( Audio::Ecasound::Multitrack::jackd_running() ){
			$track->set(jack_send => $send);
			$track->set(send_select => "jack");
			$track->jack_send
		} else {
print q(: auxilary send to JACK client specified, but jackd is not running.
Skipping.
);
			$track->aux_output;
		} 
	} else {  # must be numerical
		if ( $send <= 2){ 

			$track->set(ch_m => $send);
			$track->set(send_select =>'soundcard');
		} else { 
		print "All sends must go to soundcard channel 3 or higher. Skipping.\n";
		}
		$track->aux_output;
	}
} 

sub send_output {  # for io lists / chain setup

					# assumes $track->send exists
					
	my $track = shift;
	if ( $track->send_select eq 'soundcard' ){ 
		if (Audio::Ecasound::Multitrack::jackd_running() ){
			[qw(jack system)]
		} else {
			['device', $Audio::Ecasound::Multitrack::playback_device ]
		}
	} elsif ( $track->send_select eq 'jack' ) {
		if ( Audio::Ecasound::Multitrack::jackd_running() ){
			['jack', $track->send]
		} else {
			print $track->name, 
q(: auxilary send to JACK client specified, but jackd is not running.
Skipping.
);
			[qw(skip skip)]; 
		}
	} else { 
				q(: unexpected send_select value: "), 
				$track->send_select, qq("\n);
			[qw(skip skip)]; 
	}
}

sub source_input { # for io lists / chain setup
	my $track = shift;
	if ( $track->source_select eq 'soundcard' ){ 
		Audio::Ecasound::Multitrack::input_type_object()
	}
	elsif ( $track->source_select eq 'jack' ){
		if (Audio::Ecasound::Multitrack::jackd_running() ){
			['jack', $track->source ]
		} else { 
			print $track->name, ": no JACK client found\n";
			[qw(lost lost)]
		}
    } else { 
			print $track->name, ": missing source_select: \"",
					$track->source_select, qq("\n);
	}
}

# input channel number, may not be used in current setup

sub input {   	
	my $track = shift;
	$track->ch_r ? $track->ch_r : 1
}

# send channel number, may not be used in current setup

sub aux_output { 
	my $track = shift;
	$track->ch_m > 2 ? $track->ch_m : undef 
}

sub input_object { # for text display
	my $source = shift; # string
	$source =~ /\D/ 
		? qq(JACK client "$source")
		: qq(soundcard channel $source);
}

sub output_object {   # text for user display
	my $track = shift;
	my $send = $track->send;
	return unless $send;
	$send =~ /\D/ 
		? qq(JACK client "$send")
		: qq(soundcard channel $send);
}

sub set_rec {
	my $track = shift;
	$track->set(rw => 'REC');
	$track->rec_status eq 'REC'	or print $track->name, 
		": set to REC, but current status is ", $track->rec_status, "\n";
}
sub set_mon {
	my $track = shift;
	$track->set(rw => 'MON');
	$track->rec_status eq 'MON'	or print $track->name, 
		": set to MON, but current status is ", $track->rec_status, "\n";
}
sub set_off {
	my $track = shift;
	$track->set(rw => 'OFF');
	print $track->name, ": set to OFF\n";
}

# subclass

package Audio::Ecasound::Multitrack::SimpleTrack; # used for Master track
our @ISA = 'Audio::Ecasound::Multitrack::Track';
use Audio::Ecasound::Multitrack::Object qw( 		name
						active

						ch_r 
						ch_m 
						ch_count
						
						rw

						vol  
						pan 
						old_vol_level
						old_pan_level
						ops 
						offset 

						n 
						group 

						
						delay
						start_position
						length
						looping

						hide
						modifiers

						jack_source
						jack_send
						source_select
						send_select
						
						);

sub rec_status{

	my $track = shift;
	return 'MON' unless $track->rw eq 'OFF';
	'OFF';

}
no warnings;
sub ch_r {
	my $track = shift;
	return '';
}
use warnings;




# ---------- Group -----------

package Audio::Ecasound::Multitrack::Group;
our $VERSION = 1.0;
#use Exporter qw(import);
#our @EXPORT_OK =qw(group);
use Carp;
use vars qw(%by_name @by_index $n);
our @ISA;
$n = 0; 
@by_index = ();
%by_name = ();

use Audio::Ecasound::Multitrack::Object qw( 	name
					rw
					version 
					n	
					);

sub new {

	# returns a reference to an object that is indexed by
	# name and by an assigned index
	#
	# The indexing is bypassed and an object returned 
	# if an index is given
	
	my $class = shift;
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	croak "name missing" unless $vals{name};
	(carp "group name already in use: $vals{name}\n"), 
		return ($by_name{$vals{name}}) if $by_name{$vals{name}};
	#my $skip_index = $vals{n};
	my $n = $vals{n} ? $vals{n} : ++$n; 
	my $object = bless { 	
		name 	=> "Group $n", # default name
		rw   	=> 'REC', 
		n => $n,
		@_ 			}, $class;
	#return $object if $skip_index;
	#print "object type: ", ref $object, $/;
	$by_index[$n] = $object;
	$by_name{ $object->name } = $object;
	$object;
}


sub tracks { # returns list of track names in group 

	my $group = shift;
	my @all = Audio::Ecasound::Multitrack::Track::all;
	# map {print "type: ", ref $_, $/} Audio::Ecasound::Multitrack::Track::all; 
	map{ $_->name } grep{ $_->group eq $group->name } Audio::Ecasound::Multitrack::Track::all();
}


# all groups

sub all { @by_index[1..scalar @by_index - 1] }

# ---------- Op -----------

package Audio::Ecasound::Multitrack::Op;
our $VERSION = 0.5;
our @ISA;
use Audio::Ecasound::Multitrack::Object qw(	op_id 
					chain_id 
					effect_id
					parameters
					subcontrollers
					parent
					parent_parameter_target
					
					);


1;

# We will treat operators and controllers both as Op
# objects. Subclassing so controller has special
# add_op  and remove_op functions. 
# 

__END__

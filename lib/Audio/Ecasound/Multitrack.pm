package Audio::Ecasound::Multitrack;
use 5.008;
use Carp;
use Cwd;
use Storable; 
use Getopt::Std;
use Audio::Ecasound;
use Parse::RecDescent;
use Term::ReadLine;
use Data::YAML;
use File::Find::Rule;
use File::Spec::Link;
use File::Spec::Unix;
use File::Temp;
use IO::All;
use Event;
use Module::Load::Conditional qw(can_load);
use strict;
use strict qw(refs);
use strict qw(subs);
use warnings;
no warnings qw(uninitialized syntax);

BEGIN{ 

our $VERSION = '0.9951';

print <<BANNER;

     /////////////////////////////////////////////////////////////////////
    //                                        / /   /     ///           /
   // Nama multitrack recorder v. $VERSION                                /
  /                                    Audio processing by Ecasound 
 /       (c) 2008 Joel Roth                      ////               //
/////////////////////////////////////////////////////////////////////


BANNER


}


sub roundsleep {
	my $us = shift;
	my $sec = int( $us/1e6 + 0.5);
	$sec or $sec++;
	sleep $sec
}

if ( can_load(modules => {'Time::HiRes'=> undef} ) ) 
	 { *sleeper = *Time::HiRes::usleep }
else { *sleeper = *roundsleep }
	

# use Tk    # loaded conditionally in GUI mode

#use Module::Load;
#use Module::Load::Conditional;
#use Tk::FontDialog;


$| = 1;     # flush STDOUT buffer on every write

## Definitions ##


# 'our' declaration: all packages in the file will see the following
# variables. 

our (

    # 'our' means these variables will be accessible, without
	# package qualifiers, to all packages inhabiting 
	# the same file.
	#
	# this allows us to bring our variables from 
    # procedural core into Audio::Ecasound::Multitrack::Graphical and Audio::Ecasound::Multitrack::Text
	# packages. 
	
	# it didn't work out to be as helpful as i'd like
	# because the grammar requires package path anyway

	$help_screen, 		# 
	@help_topic,    # array of help categories
	%help_topic,    # help text indexed by topic
	$use_pager,     # display lengthy output data using pager
	$use_placeholders,  # use placeholders in show_track output
	$text,          # Text::Format object

	$ui, # object providing class behavior for graphic/text functions

	@persistent_vars, # a set of variables we save
					  	# as one big config file
	@effects_static_vars,	# the list of which variables to store and retrieve
	@effects_dynamic_vars,		# same for all chain operators
	@global_vars,    # contained in config file
	@config_vars,    # contained in config file
	@status_vars,    # we will dump them for diagnostic use
	%abbreviations, # for replacements in config files

	$globals,		# yaml assignments for @global_vars
					# for appending to config file
	
	$ecasound_globals, #  Command line switches XX check

	$default,		# the internal default configuration file, as string
					
	$raw_to_disk_format,
	$mix_to_disk_format,
	$mixer_out_format,
	
	$yw,			# yaml writer object
	$yr,			# yaml reader object
	%state_c_ops, 	# intermediate copy for storage/retrieval
	$effects_cache_file, # where we keep info on Ecasound
					# and LADSPA effects, presets, etc.
	
	$ecasound, 		# the name to invoke when we want to kill ecasound

	$grammar, 		# filled by Grammar.pm
	$parser,		# for the objected created by Parse::RecDescent
	%iam_cmd,		# for identifying IAM commands in user input
	@nama_commands,# array of commands my functions provide
	%nama_commands,# as hash as well
	$project_root,	# each project will get a directory here
	                # and one .nama directory, also with 
	
					#
					# $ENV{HOME}/.namarc
					# $ENV{HOME}/nama/paul_brocante
					# $ENV{HOME}/nama/paul_brocante/.wav/vocal_1.wav
					# $ENV{HOME}/nama/paul_brocante/Store.yml
					# $ENV{HOME}/nama/.effects_cache
					# $ENV{HOME}/nama/paul_brocante/.namarc 

					 #this_wav_dir = 
	$state_store_file,	# filename for storing @persistent_vars
	$chain_setup_file, # Ecasound uses this 

	$tk_input_channels,# this many radiobuttons appear
	                # on the menubutton
	%cfg,        # 'config' information as hash
	%devices, 		# alias to data in %cfg
	%opts,          # command line options
	%oid_status,    # state information for the chain templates
	$use_monitor_version_for_mixdown, # sync mixdown version numbers
	              	# to selected track versions , not
					# implemented
	$this_track,	 # the currently active track -- 
					 # used by Text UI only at present
	$this_op,      # currently selected effect # future
	$this_mark,    # current mark  # for future

	@format_fields, # data for replies to text commands

	$project,		# variable for GUI text input
	$project_name,	# current project name
	%state_c,		# for backwards compatilility

	### for effects

	$cop_id, 		# chain operator id, that how we create, 
					# store, find them, adjust them, and destroy them,
					# per track or per project?
	%cops,			 # chain operators stored here
	%copp,			# their parameters for effect update
	@effects,		# static effects information (parameters, hints, etc.)
	%effect_i,		# an index , pn:amp -> effect number
	%effect_j,      # an index , amp -> effect number
	@effects_help,  # one line per effect, for text search

	@ladspa_sorted, # ld
	%effects_ladspa, # parsed data from analyseplugin 
	%effects_ladspa_file, 
					# get plugin filename from Plugin Unique ID
	%ladspa_unique_id, 
					# get plugin unique id from plugin label
	%ladspa_label,  # get plugin label from unique id
	%ladspa_help,   # plugin_label => analyseplugin output
	$e,				# the name of the variable holding
					# the Ecasound engine object.
					
	%e_bound,		# for displaying hundreds of effects in groups
	$unit,			# jump multiplier, 1 or 60 seconds
	%old_vol,		# a copy of volume settings, for muting
	$length,		# maximum duration of the recording/playback if known
 	$jack_system,   # jack soundcard device
	$jack_running,  # jackd status (pid)

	@input_chains,	# list of input chain segments 
	@output_chains, # list of output chain segments

	%subst,			# alias, substitutions for the config file
	$tkeca_effects_data,	# original tcl code, actually

	### Widgets
	
	$mw, 			# main window
	$ew, 			# effects window
	$canvas, 		# to lay out the effects window

	# each part of the main window gets its own frame
	# to control the layout better

	$load_frame,
	$add_frame,
	$group_frame,
	$time_frame,
	$clock_frame,
	$oid_frame,
	$track_frame,
	$effect_frame,
	$iam_frame,
	$perl_eval_frame,
	$transport_frame,
	$mark_frame,
	$fast_frame, # forward, rewind, etc.

	## collected widgets (i may need to destroy them)

	%parent, # ->{mw} = $mw; # main window
			 # ->{ew} = $ew; # effects window
			 # eventually will contain all major frames
	$group_label, 
	$group_rw, # 
	$group_version, # 
	%track_widget, # for chains (tracks)
	%effects_widget, # for effects
	@widget_o, # for templates (oids) 
	%widget_o, # 
	%mark_widget, # marks

	@global_version_buttons, # to set the same version for
						  	#	all tracks
	%marks, 		# the actual times
	$markers_armed, # set true to enable removing a mark
	$mark_remove,   # a button that sets $markers_armed
	$time_step,     # widget shows jump multiplier unit (seconds or minutes)
	$clock, 		# displays clock
	$setup_length,  # displays setup running time

	$project_label,	# project name

	$sn_label,		# project load/save/quit	
	$sn_text,
	$sn_load,
	$sn_new,
	$sn_quit,
	$sn_palette, # configure colors
	$sn_namapalette, # configure nama colors
	@palettefields, # set by setPalette method
	@namafields,    # field names for color palette used by nama
	%namapalette,     # nama's indicator colors
	%palette,  # overall color scheme
	$rec,      # background color
	$mon,      # background color
	$off,      # background color
	$palette_file, # where to save selections

	### A separate box for entering IAM (and other) commands
	$iam_label,
	$iam_text,
	$iam, # variable for text entry
	$iam_execute,
	$iam_error, # unused

	# add track gui
	#
	$build_track_label,
	$build_track_text,
	$build_track_add_mono,
	$build_track_add_stereo,
	$build_track_rec_label,
	$build_track_rec_text,
	$build_track_mon_label,
	$build_track_mon_text,

	$build_new_take,

	# transport controls
	
	$transport_label,
	$transport_setup_and_connect,
	$transport_setup, # unused
	$transport_connect, # unused
	$transport_disconnect,
	$transport_new,
	$transport_start,
	$transport_stop,

	$old_bg, # initial background color.
	$old_abg, # initial active background color


	$loopa,  # loopback nodes 
	$loopb,  

	@oids,	# output templates, are applied to the
			# chains collected previously
			# the results are grouped as
			# input, output and intermediate sections

	%inputs,
	%outputs,
	%post_input,
	%pre_output,

	$ladspa_sample_rate,	# used as LADSPA effect parameter fixed at 44100

	$track_name,	# received from Tk text input form
	%track_names,   # belongs in Track.pm
	$ch_r,			# recording channel assignment
	$ch_m,			# monitoring channel assignment


	%L,	# for effects
	%M,
	$debug,				# debug level flags for diagnostics
	$debug2,			# for subroutine names as execute
	$debug3,			# deprecated
						
	$OUT,				# filehandle for Text mode print
	#$commands,	# ref created from commands.yml
	%commands,	# created from commands.yml
	%dispatch,  # replacement for existing parser
	$commands_yml, # the string form of commands.yml
	$cop_hints_yml, # ecasound effects hinting

	$save_id, # text variable
	$sn_save_text,# text entry widget
	$sn_save,	# button to save settings
	$sn_recall,	# button to recall settings
	$sn_dump,  # button to dump status

	# new object core
	
	$tracker_bus, 
	$tracker, # tracker_group
	$master_bus, 
	$master, # master_group
	$master_track,
	$mixdown_bus,
	$mixdown,  # group
	$mixdown_track,
	$null_bus,
    $null, # group

	@ti, # track by index (alias @Audio::Ecasound::Multitrack::Track::by_index)
	%tn, # track by name  (alias %Audio::Ecasound::Multitrack::Track::by_name)

	@tracks_data, # staging for saving
	@groups_data, # 
	@marks_data, # 

	$playback_device,       # where to send stereo output
	$playback_device_jack,  # JACK target for stereo output
	$capture_device,    # where to get our inputs
	$capture_device_jack,    # where to get our inputs


	# rules
	
	$mixer_out,
	$mix_down,
	$mix_link,
	$mix_setup,
	$mix_setup_mon,
	$mon_setup,
	$rec_file,
	$rec_setup,
	$multi,
	$null_setup,

   # marks and playback looping
   
	$clock_id,		# used in GUI for the Tk event system
					# ->cancel method not reliable
					# for 'repeat' events, so converted to
					# 'after' events
	%event_id,    # events will store themselves with a key
	$set_event,   # the Tk dummy widget used to set events
	@loop_endpoints, # they define the loop
	$loop_enable, # whether we automatically loop

   $previous_text_command, # i want to know if i'm repeating
	$term, 			# Term::ReadLine object
	$controller_ports, # where we listen for MIDI messages
    $midi_inputs,  # on/off/capture

	@already_muted, # for soloing list of Track objects that are 
                    # muted before we begin
    $soloing,       # one user track is on, all others are muted

	%bunch,			# user collections of tracks
	@keywords,      # for autocompletion
	$seek_delay,    # allow microseconds for transport seek
                    # (used with JACK only)
    $prompt,        # for text mode
	$preview,       # am running engine with rec_file disabled
	$use_group_numbering, # same version number for tracks recorded together
	$unique_inputs_only,  # exclude tracks sharing same source
	%excluded,      # tracks sharing source with other tracks,
	                # after the first
	$memoize,       # do I cache this_wav_dir?

);
 


@global_vars = qw(
						$effects_cache_file
						$ladspa_sample_rate
						$state_store_file
						$chain_setup_file
						$tk_input_channels
						$use_monitor_version_for_mixdown 
						$unit								);
						
@config_vars = qw(
						%abbreviations
						%devices
						$ecasound_globals
						$mix_to_disk_format
						$raw_to_disk_format
						$mixer_out_format
						$playback_device
						$capture_device	
						$project_root 	
						$use_group_numbering
						);

						
						

@persistent_vars = qw(

						%cops 			
						$cop_id 		
						%copp 			
						%marks			
						$unit			
						%oid_status		
						%old_vol		
						$this_op
						@tracks_data
						@groups_data
						@marks_data
						$loop_enable
						@loop_endpoints
						$length
						%bunch
						$memoize
						);
					 
@effects_static_vars = qw(

						@effects		
						%effect_i	
						%effect_j	
						%e_bound
						@ladspa_sorted
						%effects_ladspa	
						%effects_ladspa_file
						%ladspa_unique_id
						%ladspa_label
						%ladspa_help
						@effects_help
						);
					


@effects_dynamic_vars = qw(

						%state_c_ops
						%cops    
						$cop_id     
						%copp   
						@marks 	
						$unit				);



@status_vars = qw(

						%state_c
						%state_t
						%copp
						%cops
						%post_input
						%pre_output   
						%inputs
						%outputs      );




# instances needed for yaml_out and yaml_in

$yw = Data::YAML::Writer->new; 
$yr = Data::YAML::Reader->new;

$debug2 = 0; # subroutine names
$debug = 0; # debug statements

## The names of two helper loopback devices:

$loopa = 'loop,111';
$loopb = 'loop,222';

# other initializations
$unit = 1;
$effects_cache_file = '.effects_cache';
$palette_file = 'palette.yml';
$state_store_file = 'State';
$chain_setup_file = 'Setup.ecs'; # For loading by Ecasound
$tk_input_channels = 10;
$use_monitor_version_for_mixdown = 1; # not implemented yet
$project_root = join_path( $ENV{HOME}, "nama");
$seek_delay = 100_000; # microseconds
$prompt = "nama ('h' for help)> ";
$use_pager = 1;
$use_placeholders = 1;
$jack_running = jack_running(); # to be updated by Event
$memoize = 0;


## Load my modules

use Audio::Ecasound::Multitrack::Assign qw(:all);
use Audio::Ecasound::Multitrack::Tkeca_effects; 
use Audio::Ecasound::Multitrack::Track;
use Audio::Ecasound::Multitrack::Bus;    
use Audio::Ecasound::Multitrack::Mark;
use Audio::Ecasound::Multitrack::Wav;

package Audio::Ecasound::Multitrack::Wav;
memoize('candidates') if $Audio::Ecasound::Multitrack::memoize;
package Audio::Ecasound::Multitrack;

# aliases for concise access

*tn = \%Audio::Ecasound::Multitrack::Track::by_name;
*ti = \@Audio::Ecasound::Multitrack::Track::by_index;

# $ti[3]->rw

# print remove_spaces("bulwinkle is a...");

## Class and Object definitions for package 'Audio::Ecasound::Multitrack'

our @ISA; # no anscestors
use Audio::Ecasound::Multitrack::Object qw(mode);

## The following methods belong to the root class

sub hello {"superclass hello"}

sub new { my $class = shift; return bless {@_}, $class }

use Carp;

sub mainloop { 
	prepare(); 
	$ui->loop;
}
sub status_vars {
	serialize( -class => 'Audio::Ecasound::Multitrack', -vars => \@status_vars);
}
sub config_vars {
	serialize( -class => 'Audio::Ecasound::Multitrack', -vars => \@config_vars);
}

sub discard_object {
	shift @_ if (ref $_[0]) =~ /Multitrack/;  # HARDCODED
	@_;
}



sub first_run {
my $config = config_file();
$config = "$ENV{HOME}/$config" unless -e $config;
$debug and print "config: $config\n";
if ( ! -e $config and ! -l $config  ) {

# check for missing components

my $missing;
my @a = `which analyseplugin`;
@a or print ( <<WARN
LADSPA helper program 'analyseplugin' not found
in $ENV{PATH}, your shell's list of executable 
directories. You will probably have more fun with the LADSPA
libraries and executables installed. http://ladspa.org
WARN
) and  sleeper (600_000) and $missing++;
my @b = `which ecasound`;
@b or print ( <<WARN
Ecasound executable program 'ecasound' not found
in $ENV{PATH}, your shell's list of executable 
directories. This suite depends on the Ecasound
libraries and executables for all audio processing! 
WARN
) and sleeper (600_000) and $missing++;

my @c = `which file`;
@c or print ( <<WARN
BSD utility program 'file' not found
in $ENV{PATH}, your shell's list of executable 
directories. This program is currently required
to be able to play back mixes in stereo.
WARN
) and sleeper (600_000);
if ( $missing ) {
print "You lack $missing main parts of this suite.  
Do you want to continue? [N] ";
$missing and 
my $reply = <STDIN>;
chomp $reply;
print ("Goodbye.\n"), exit unless $reply =~ /y/i;
}
print <<HELLO;

Aloha. Welcome to Nama and Ecasound.

HELLO
sleeper (600_000);
print "Configuration file $config not found.

May I create it for you? [yes] ";
my $make_namarc = <STDIN>;
sleep 1;
print <<PROJECT_ROOT;

Nama places all sound and control files under the
project root directory, by default $ENV{HOME}/nama.

PROJECT_ROOT
print "Would you like to create $ENV{HOME}/nama? [yes] ";
my $reply = <STDIN>;
chomp $reply;
if ($reply !~ /n/i){
	$default =~ s/^project_root.*$/project_root: $ENV{HOME}\/nama/m;
	create_dir( $project_root);
	create_dir( join_path $project_root, "untitled");
} else {
	print <<OTHER;
Please make sure to set the project_root directory in
.namarc, or on the command line using the -d option.

OTHER
}
if ($make_namarc !~ /n/i){
$default > io( $config );
}
sleep 1;
print "\n.... Done!\n\nPlease edit $config and restart Nama.\n\n";
print "Exiting.\n"; 
exit;	
}
}
	
	
sub prepare {  
	

	$debug2 and print "&prepare\n";
	

	$ecasound  = $ENV{ECASOUND} ? $ENV{ECASOUND} : q(ecasound);
	$e = Audio::Ecasound->new();
	#new_engine();
	
	
	$debug and print "started Ecasound\n";

	### Option Processing ###
	# push @ARGV, qw( -e  );
	#push @ARGV, qw(-d /media/sessions test-abc  );
	getopts('amcegstrd:f:', \%opts); 
	#print join $/, (%opts);
	# a: save and reload ALSA state using alsactl
	# d: set project root dir
	# c: create project
	# f: specify configuration file
	# g: gui mode (default)
	# t: text mode 
	# m: don't load state info on initial startup
	# r: regenerate effects data cache
	# e: don't load static effects data (for debugging)
	# s: don't load static effects data cache (for debugging)
	
	get_ecasound_iam_keywords();

	# load Tk only in graphic mode
	
	if ($opts{t}) {}
	else { 
		require Tk;
		Tk->import;
	}

	$project_name = shift @ARGV;
	$debug and print "project name: $project_name\n";

	$debug and print ("\%opts\n======\n", yaml_out(\%opts)); ; 


	read_config();  # from .namarc if we have one

	$debug and print "reading config file\n";
	$project_root = $opts{d} if $opts{d}; # priority to command line option

	$project_root or $project_root = join_path($ENV{HOME}, "nama" );

	# capture the sample frequency from .namarc
	($ladspa_sample_rate) = $devices{jack}{signal_format} =~ /(\d+)(,i)?$/;

	first_run();
	
	# init our buses
	
	$tracker_bus  = Audio::Ecasound::Multitrack::Bus->new(
		name => 'Tracker_Bus',
		groups => [qw(Tracker)],
		tracks => [],
		rules  => [ qw( mix_setup rec_setup mon_setup multi rec_file) ],
	);

	# print join (" ", map{ $_->name} Audio::Ecasound::Multitrack::Rule::all_rules() ), $/;

	$master_bus  = Audio::Ecasound::Multitrack::Bus->new(
		name => 'Master_Bus',
		rules  => [ qw(mixer_out mix_link) ],
		groups => ['Master'],
	);
	$mixdown_bus  = Audio::Ecasound::Multitrack::Bus->new(
		name => 'Mixdown_Bus',
		groups => [qw(Mixdown) ],
		rules  => [ qw(mon_setup mix_setup_mon  mix_file ) ],
	);
	$null_bus = Audio::Ecasound::Multitrack::Bus->new(
		name => 'Null_Bus',
		groups => [qw(null) ],
		rules => [qw(null_setup)],
	);


	prepare_static_effects_data() unless $opts{e};

	load_keywords(); # for autocompletion
	chdir $project_root # for filename autocompletion
		or warn "$project_root: chdir failed: $!\n";

	prepare_command_dispatch(); 

	#print "keys effect_i: ", join " ", keys %effect_i;
	#map{ print "i: $_, code: $effect_i{$_}->{code}\n" } keys %effect_i;
	#die "no keys";	
	
	# UI object for interface polymorphism
	
	$ui = $opts{t} ? Audio::Ecasound::Multitrack::Text->new 
				   : Audio::Ecasound::Multitrack::Graphical->new ;

	# default to graphic mode  (Tk event loop)
	# text mode (Event.pm event loop)

	$ui->init_gui;
	$ui->transport_gui;
	$ui->time_gui;

	if (! $project_name ){
		$project_name = "untitled";
		$opts{c}++; 
	}
	print "project_name: $project_name\n";
	
	load_project( name => $project_name, create => $opts{c}) 
	  if $project_name;

	$debug and print "project_root: ", project_root(), $/;
	$debug and print "this_wav_dir: ", this_wav_dir(), $/;
	$debug and print "project_dir: ", project_dir() , $/;
	1;	
}




sub eval_iam{
	$debug2 and print "&eval_iam\n";
	my $command = shift;
	$debug and print "iam command: $command\n";
	my (@result) = $e->eci($command);
	$debug and print "result: @result\n" unless $command =~ /register/;
	my $errmsg = $e->errmsg();
	# $errmsg and carp("IAM WARN: ",$errmsg), 
	# not needed ecasound prints error on STDOUT
	$e->errmsg('');
	"@result";
}
sub colonize { # convert seconds to hours:minutes:seconds 
	my $sec = shift;
	my $hours = int ($sec / 3600);
	$sec = $sec % 3600;
	my $min = int ($sec / 60);
	$sec = $sec % 60;
	$sec = "0$sec" if $sec < 10;
	$min = "0$min" if $min < 10 and $hours;
	($hours ? "$hours:" : "") . qq($min:$sec);
}

## configuration file

sub project_root { File::Spec::Link->resolve_all($project_root)};

sub config_file { $opts{f} ? $opts{f} : ".namarc" }
sub this_wav_dir {
	$project_name and
	File::Spec::Link->resolve_all(
		join_path( project_root(), $project_name, q(.wav) )  
	);
}
sub project_dir  {$project_name and join_path( project_root(), $project_name)
}

sub global_config{
print ("reading config file $opts{f}\n"), return io( $opts{f})->all if $opts{f} and -r $opts{f};
my @search_path = (project_dir(), $ENV{HOME}, project_root() );
my $c = 0;
	map{ 
#print $/,++$c,$/;
			if (-d $_) {
				my $config = join_path($_, config_file());
				#print "config: $config\n";
				if( -f $config ){ 
					my $yml = io($config)->all ;
					return $yml;
				}
			}
		} ( @search_path) 
}

sub read_config {
	$debug2 and print "&read_config\n";
	
	my $config = shift;
	#print "config: $config";;
	my $yml = length $config > 100 ? $config : $default;
	#print "yml1: $yml";
	strip_all( $yml );
	#print "yml2: $yml";
	if ($yml !~ /^---/){
		$yml =~ s/^\n+//s;
		$yml =~ s/\n+$//s;
		$yml = join "\n", "---", $yml, "...";
	}
#	print "yml3: $yml";
	eval ('$yr->read($yml)') or croak( "Can't read YAML code: $@");
	%cfg = %{  $yr->read($yml)  };
	#print yaml_out( $cfg{abbreviations}); exit;
	*subst = \%{ $cfg{abbreviations} }; # alias
#	*devices = \%{ $cfg{devices} }; # alias
#	assigned by assign_var below
	#print yaml_out( \%subst ); exit;
	walk_tree(\%cfg);
	walk_tree(\%cfg); # second pass completes substitutions
	assign_var( \%cfg, @config_vars); 
	#print "config file: $yml";

}
sub walk_tree {
	#$debug2 and print "&walk_tree\n";
	my $ref = shift;
	map { substitute($ref, $_) } 
		grep {$_ ne q(abbreviations)} 
			keys %{ $ref };
}
sub substitute{
	my ($parent, $key)  = @_;
	my $val = $parent->{$key};
	#$debug and print qq(key: $key val: $val\n);
	ref $val and walk_tree($val)
		or map{$parent->{$key} =~ s/$_/$subst{$_}/} keys %subst;
}
## project handling

sub list_projects {
	my $cmd = "ls ". project_root();
	print system $cmd;
}
sub list_plugins {}
		
sub load_project {
	$debug2 and print "&load_project\n";
	#carp "load project: I'm being called from somewhere!\n";
	my %h = @_;
	$debug and print yaml_out \%h;
	print ("no project name.. doing nothing.\n"),return unless $h{name} or $project;

	# we could be called from Tk with variable $project _or_
	# called with a hash with 'name' and 'create' fields.
	
	my $project = remove_spaces($project); # internal spaces to underscores
	$project_name = $h{name} if $h{name};
	$project_name = $project if $project;
	$debug and print "project name: $project_name create: $h{create}\n";
	$project_name and $h{create} and 
		#print ("Creating directories....\n"),
		map{create_dir($_)} &project_dir, &this_wav_dir ;
	read_config( global_config() ); 
	initialize_rules();
	initialize_project_data();
	remove_small_wavs(); 
	rememoize();

	retrieve_state( $h{settings} ? $h{settings} : $state_store_file) unless $opts{m} ;
	$opts{m} = 0; # enable 
	
	#print "Track_by_index: ", $#Audio::Ecasound::Multitrack::Track::by_index, $/;
	dig_ruins() unless $#Audio::Ecasound::Multitrack::Track::by_index > 2;

	# possible null if Text mode
	
	$ui->global_version_buttons(); 
	$ui->refresh_group;
	generate_setup() and connect_transport();

#The mixed signal is always output at track index 1 i.e. 
# The corresponding object is found by $ti[$n]
# for $n = 1. 
 1;

}

sub initialize_rules {

	package Audio::Ecasound::Multitrack::Rule;
		$n = 0;
		@by_index = ();	# return ref to Track by numeric key
		%by_name = ();	# return ref to Track by name
		%rule_names = (); 
	package Audio::Ecasound::Multitrack;

	$mixer_out = Audio::Ecasound::Multitrack::Rule->new( #  this is the master output
		name			=> 'mixer_out', 
		chain_id		=> 1, # MixerOut

		target			=> 'MON',

	# condition =>	sub{ defined $inputs{mixed}  
	# 	or $debug and print("no customers for mixed, skipping\n"), 0},

		input_type 		=> 'mixed', # bus name
		input_object	=> $loopb, 

		output_type		=> sub{ ${output_type_object()}[0] },
		output_object	=> sub{ ${output_type_object()}[1] },

		status			=> 1,

	);

	$mix_down = Audio::Ecasound::Multitrack::Rule->new(

		name			=> 'mix_file', 
		chain_id		=> 2, # MixDown
		target			=> 'REC', 
		
		# sub{ defined $outputs{mixed} or $debug 
		#		and print("no customers for mixed, skipping mixdown\n"), 0}, 

		input_type 		=> 'mixed', # bus name
		input_object	=> $loopb,

		output_type		=> 'file',


		# - a hackish conditional way to include the mixdown format
		# - seems to work
		# - it would be better to add another output type

		output_object   => sub {
			my $track = shift; 
			join " ", $track->full_path, $mix_to_disk_format},

		status			=> 1,
	);

	$mix_link = Audio::Ecasound::Multitrack::Rule->new(

		name			=>  'mix_link',
		chain_id		=>  'MixLink',
		#chain_id		=>  sub{ my $track = shift; $track->n },
		target			=>  'all',
		condition =>	sub{ defined $inputs{mixed}->{$loopb} },
		input_type		=>  'mixed',
		input_object	=>  $loopa,
		output_type		=>  'mixed',
		output_object	=>  $loopb,
		status			=>  1,
		
	);

	$mix_setup = Audio::Ecasound::Multitrack::Rule->new(

		name			=>  'mix_setup',
		chain_id		=>  sub { my $track = shift; "J". $track->n },
		target			=>  'all',
		input_type		=>  'cooked',
		input_object	=>  sub { my $track = shift; "loop," .  $track->n },
		output_object	=>  $loopa,
		output_type		=>  'cooked',
		condition 		=>  sub{ defined $inputs{mixed}->{$loopb} },
		status			=>  1,
		
	);

	$mix_setup_mon = Audio::Ecasound::Multitrack::Rule->new(

		name			=>  'mix_setup_mon',
		chain_id		=>  sub { my $track = shift; "K". $track->n },
		target			=>  'MON',
		input_type		=>  'cooked',
		input_object	=>  sub { my $track = shift; "loop," .  $track->n },
		output_object	=>  $loopa,
		output_type		=>  'cooked',
		# condition 		=>  sub{ defined $inputs{mixed} },
		condition        => 1,
		status			=>  1,
		
	);



	$mon_setup = Audio::Ecasound::Multitrack::Rule->new(
		
		name			=>  'mon_setup', 
		target			=>  'MON',
		chain_id 		=>	sub{ my $track = shift; $track->n },
		input_type		=>  'file',
		input_object	=>  sub{ my $track = shift; $track->full_path },
		output_type		=>  'cooked',
		output_object	=>  sub{ my $track = shift; "loop," .  $track->n },
		post_input		=>	sub{ my $track = shift; $track->mono_to_stereo},
		condition 		=> 1,
		status			=>  1,
	);
		
	$rec_file = Audio::Ecasound::Multitrack::Rule->new(

		name		=>  'rec_file', 
		target		=>  'REC',
		chain_id	=>  sub{ my $track = shift; 'R'. $track->n },   
		input_type		=> sub{ my $track = shift;
								${$track->source_input}[0] },
		input_object		=> sub{ my $track = shift;
								${$track->source_input}[1] },
		output_type	=>  'file',
		output_object   => sub {
			my $track = shift; 
			my $format = signal_format($raw_to_disk_format, $track->ch_count);
			join " ", $track->full_path, $format
		},
		post_input			=>	sub{ my $track = shift;
										$track->rec_route 
										},
		status		=>  1,
	);

	# Rec_setup: must come last in oids list, convert REC
	# inputs to stereo and output to loop device which will
	# have Vol, Pan and other effects prior to various monitoring
	# outputs and/or to the mixdown file output.
			
    $rec_setup = Audio::Ecasound::Multitrack::Rule->new(

		name			=>	'rec_setup', 
		chain_id		=>  sub{ my $track = shift; $track->n },   
		target			=>	'REC',
		input_type		=> sub{ my $track = shift;
								${$track->source_input}[0] },
		input_object	=> sub{ my $track = shift;
								${$track->source_input}[1] },
		output_type		=>  'cooked',
		output_object	=>  sub{ my $track = shift; "loop," .  $track->n },
		post_input			=>	sub{ my $track = shift;
										$track->rec_route .
										$track->mono_to_stereo 
										},
		condition 		=> sub { my $track = shift; 
								return "satisfied" if defined
								$inputs{cooked}->{"loop," . $track->n}; 
								} ,
		status			=>  1,
	);

	# route cooked signals to multichannel device in the 
	# case that monitor_channel is specified
	#
	# thus we could apply guitar effects for output
	# to a PA mixing board
	#
	# seems ready... just need to turn on status!

# the following two subs are utility functions for multi
# assume $track->send returns nonzero, non null
# applies to $track->send only


	
$multi = Audio::Ecasound::Multitrack::Rule->new(  

		name			=>  'multi', 
		target			=>  'all',
		chain_id 		=>	sub{ my $track = shift; "M".$track->n },
		input_type		=>  'cooked', 
		input_object	=>  sub{ my $track = shift; "loop," .  $track->n},
		output_type		=>  sub{ my $track = shift;
								$track->send_output->[0]},
		output_object	=>  sub{ my $track = shift;
								 $track->send_output->[1]},
		pre_output		=>	sub{ my $track = shift; $track->pre_send},
		condition 		=> sub { my $track = shift; 
								return "satisfied" if $track->send; } ,
		status			=>  1,
	);

	$null_setup = Audio::Ecasound::Multitrack::Rule->new(
		
		name			=>  'null_setup', 
		target			=>  'all',
		chain_id 		=>	sub{ my $track = shift; $track->n },
		input_type		=>  'device',
		input_object	=>  'null',
		output_type		=>  'cooked',
		output_object	=>  $loopa,
		condition 		=>  sub{ defined $inputs{mixed}->{$loopb} },
		status			=>  1,
# 		output_object	=>  sub{ my $track = shift; "loop," .  $track->n },
		post_input		=>	sub{ my $track = shift; $track->mono_to_stereo},
		condition 		=> 1,
		status			=>  1,
	);
		

	$ui->preview_button;

}

sub jack_running { qx(pgrep jackd) }
sub engine_running {
	eval_iam("engine-status") eq "running"
};

sub input_type_object {
	if ($jack_running ){ 
		[qw(jack system)] 
	} else { 
	    [ q(device), $capture_device  ]
	}
}
sub output_type_object {
	if ($jack_running ){ 
		[qw(jack system)] 
	} else { 
	    [ q(device), $playback_device  ]
	}
}

	
sub eliminate_loops {
	$debug2 and print "&eliminate_loops\n";
	# given track
	my $n = shift;
	my $loop_id = "loop,$n";
	return unless defined $inputs{cooked}->{$loop_id} 
		and scalar @{$inputs{cooked}->{$loop_id}} == 1;
	# get customer's id from cooked list and remove it from the list

	my $cooked_id = pop @{ $inputs{cooked}->{$loop_id} }; 

	# i.e. J3

	# add chain $n to the list of the customer's (rule's) output device 
	
	#my $rule  = grep{ $cooked_id =~ /$_->chain_id/ } Audio::Ecasound::Multitrack::Rule::all_rules();  
	my $rule = $mix_setup; 
	defined $outputs{cooked}->{$rule->output_object} 
	  or $outputs{cooked}->{$rule->output_object} = [];
	push @{ $outputs{cooked}->{$rule->output_object} }, $n;


	# remove chain $n as source for the loop

	delete $outputs{cooked}->{$loop_id}; 
	
	# remove customers that use loop as input

	delete $inputs{cooked}->{$loop_id}; 

	# remove cooked customer from his output device list
	# print "customers of output device ",
	#	$rule->output_object, join " ", @{
	#		$outputs{cooked}->{$rule->output_object} };
	#
	@{ $outputs{cooked}->{$rule->output_object} } = 
		grep{$_ ne $cooked_id} @{ $outputs{cooked}->{$rule->output_object} };

	#print $/,"customers of output device ",
	#	$rule->output_object, join " ", @{
	#		$outputs{cooked}->{$rule->output_object} };
	#		print $/;

	# transfer any intermediate processing to numeric chain,
	# deleting the source.
	$post_input{$n} .= $post_input{$cooked_id};
	$pre_output{$n} .= $pre_output{$cooked_id}; 
	delete $post_input{$cooked_id};
	delete $pre_output{$cooked_id};

	# remove loopb when only one customer for  $inputs{mixed}{loop,222}
	
	my $ref = ref $inputs{mixed}{$loopb};

	if (    $ref =~ /ARRAY/ and 
			(scalar @{$inputs{mixed}{$loopb}} == 1) ){

		$debug and print "i have a loop to eliminate \n";
		my $customer_id = ${$inputs{mixed}{$loopb}}[0];
		$debug and print "customer chain: $customer_id\n";

		delete $outputs{mixed}{$loopb};
		delete $inputs{mixed}{$loopb};

	$inputs{mixed}{$loopa} = [ $customer_id ];

	}
	
}

sub initialize_project_data {
	$debug2 and print "&initialize_project_data\n";

	return if transport_running();
	$ui->destroy_widgets();
	$ui->project_label_configure(
		-text => uc $project_name, 
		-background => 'lightyellow',
		); 

	# assign_var($project_init_file, @project_vars);

	%cops        = ();   
	$cop_id           = "A"; # autoincrement
	%copp           = ();    # chain operator parameters, dynamic
	                        # indexed by {$id}->[$param_no]
							# and others
	%old_vol = ();

	@input_chains = ();
	@output_chains = ();

	%track_widget = ();
	%effects_widget = ();
	

	# time related
	
	$markers_armed = 0;
	%marks = ();

	# new Marks
	# print "original marks\n";
	#print join $/, map{ $_->time} Audio::Ecasound::Multitrack::Mark::all();
 	map{ $_->remove} Audio::Ecasound::Multitrack::Mark::all();
	@marks_data = ();
	#print "remaining marks\n";
	#print join $/, map{ $_->time} Audio::Ecasound::Multitrack::Mark::all();
	# volume settings
	
	%old_vol = ();

	# $is_armed = 0;
	
	%bunch = ();	
	
	$Audio::Ecasound::Multitrack::Group::n = 0; 
	@Audio::Ecasound::Multitrack::Group::by_index = ();
	%Audio::Ecasound::Multitrack::Group::by_name = ();

	$Audio::Ecasound::Multitrack::Track::n = 0; 	# incrementing numeric key
	@Audio::Ecasound::Multitrack::Track::by_index = ();	# return ref to Track by numeric key
	%Audio::Ecasound::Multitrack::Track::by_name = ();	# return ref to Track by name
	%Audio::Ecasound::Multitrack::Track::track_names = (); 

	$master = Audio::Ecasound::Multitrack::Group->new(name => 'Master');
	$mixdown =  Audio::Ecasound::Multitrack::Group->new(name => 'Mixdown', rw => 'REC');
	$tracker = Audio::Ecasound::Multitrack::Group->new(name => 'Tracker', rw => 'REC');
	$null    = Audio::Ecasound::Multitrack::Group->new(name => 'null');

	#print yaml_out( \%Audio::Ecasound::Multitrack::Track::track_names );


# create magic tracks, we will create their GUI later, after retrieve

	$master_track = Audio::Ecasound::Multitrack::SimpleTrack->new( 
		group => 'Master', 
		name => 'Master',
		rw => 'MON',); # no dir, we won't record tracks


	$mixdown_track = Audio::Ecasound::Multitrack::Track->new( 
		group => 'Mixdown', 
		name => 'Mixdown', 
		rw => 'MON'); 

}
## track and wav file handling

sub add_track {

	@_ = discard_object(@_);
	$debug2 and print "&add_track\n";
	return if transport_running();
	my @names = @_;
	for my $name (@names){
		my $name = shift;
		$debug and print "name: $name, ch_r: $ch_r, ch_m: $ch_m\n";
		my $track = Audio::Ecasound::Multitrack::Track->new(
			name => $name,
		);
		$this_track = $track;
		return if ! $track; 
		$debug and print "ref new track: ", ref $track; 
		$track->source($ch_r) if $ch_r;
#		$track->send($ch_m) if $ch_m;

		my $group = $Audio::Ecasound::Multitrack::Group::by_name{$track->group};
		$group->set(rw => 'REC');
		$track_name = $ch_m = $ch_r = undef;

		$ui->track_gui($track->n);
		$debug and print "Added new track!\n", $track->dump;
	}
}

sub dig_ruins { 
	

	# only if there are no tracks , 
	
	$debug2 and print "&dig_ruins";
	return if $tracker->tracks;
	$debug and print "looking for WAV files\n";

	# look for wave files
		
		my $d = this_wav_dir();
		opendir WAV, $d or carp "couldn't open $d: $!";

		# remove version numbers
		
		my @wavs = grep{s/(_\d+)?\.wav//i} readdir WAV;

		my %wavs;
		
		map{ $wavs{$_}++ } @wavs;
		@wavs = keys %wavs;

		$debug and print "tracks found: @wavs\n";
	 
		$ui->create_master_and_mix_tracks();

		map{add_track($_)}@wavs;

#	}
}

sub remove_small_wavs {

	# 44 byte stubs left by a recording chainsetup that is 
	# connected by not started
	
	$debug2 and print "&remove_small_wavs\n";
	

	$debug and print "this wav dir: ", this_wav_dir(), $/;
	return unless this_wav_dir();
         my @wavs = File::Find::Rule ->name( qr/\.wav$/i )
                                        ->file()
                                        ->size(44)
                                        ->extras( { follow => 1} )
                                     ->in( this_wav_dir() );
    $debug and print join $/, @wavs;

	map { unlink $_ } @wavs; 
}

sub add_volume_control {
	my $n = shift;
	
	my $vol_id = cop_add({
				chain => $n, 
				type => 'ea',
				cop_id => $ti[$n]->vol, # often undefined
				});
	
	$ti[$n]->set(vol => $vol_id);  # save the id for next time
	$vol_id;
}
sub add_pan_control {
	my $n = shift;
	
	my $pan_id = cop_add({
				chain => $n, 
				type => 'epp',
				cop_id => $ti[$n]->pan, # often undefined
				});
	
	$ti[$n]->set(pan => $pan_id);  # save the id for next time
	$pan_id;
}
## version functions


sub mon_vert {
	my $ver = shift;
	$tracker->set(version => $ver);
	$ui->refresh();
}
## chain setup generation


sub all_chains {
	my @active_tracks = grep { $_->rec_status ne q(OFF) } Audio::Ecasound::Multitrack::Track::all() 
		if Audio::Ecasound::Multitrack::Track::all();
	map{ $_->n} @active_tracks if @active_tracks;
}

sub user_rec_tracks {
	my @user_tracks = Audio::Ecasound::Multitrack::Track::all();
	splice @user_tracks, 0, 2; # drop Master and Mixdown tracks
	return unless @user_tracks;
	my @user_rec_tracks = grep { $_->rec_status eq 'REC' } @user_tracks;
	return unless @user_rec_tracks;
	map{ $_->n } @user_rec_tracks;
}
sub user_mon_tracks {
	my @user_tracks = Audio::Ecasound::Multitrack::Track::all();
	splice @user_tracks, 0, 2; # drop Master and Mixdown tracks
	return unless @user_tracks;
	my @user_mon_tracks = grep { $_->rec_status eq 'MON' } @user_tracks;
	return unless @user_mon_tracks;
	map{ $_->n } @user_mon_tracks;

}

sub really_recording {  # returns $output{file} entries

#	scalar @record  
	#print join "\n", "", ,"file recorded:", keys %{$outputs{file}}; # includes mixdown
# 	map{ s/ .*$//; $_}  # unneeded
	keys %{$outputs{file}}; # strings include format strings mixdown
}

sub write_chains {
	$debug2 and print "&write_chains\n";

	# $bus->apply;
	# $mixer->apply;
	# $ui->write_chains

	# we can assume that %inputs and %outputs will have the
	# same lowest-level keys
	#
	my @buses = grep { $_ !~ /file|device|jack/ } keys %inputs;
	
	### Setting devices as inputs 

		# these inputs are generated by rec_setup
	
	for my $dev (keys %{ $inputs{device} } ){

		$debug and print "dev: $dev\n";
		my @chain_ids = @{ $inputs{device}->{$dev} };
		#print "found ids: @chain_ids\n";

		# case 1: if $dev appears in config file %devices listing
		#         we treat $dev is a sound card
		
		if ( $devices{$dev} ){
			push  @input_chains, 
			join " ", "-a:" . (join ",", @chain_ids),
			$devices{$dev}->{input_format} 
				? "-f:" .  $devices{$dev}->{input_format}
				: q(),
				"-i:" .  $devices{$dev}->{ecasound_id}, 
		} else { print <<WARN;
chains @chain_ids: device $dev not found in .namarc.  Skipping.

WARN
		}

	}

	#####  Setting jack clients as inputs
 
	for my $client (keys %{ $inputs{jack} } ){

		my @chain_ids = @{ $inputs{jack}->{$client} };
		my $format;

		if ( $client eq 'system' ){ # we use the full soundcard width

			$format = signal_format(
				$devices{jack}->{signal_format},

				# client's output is our input
				jack_client($client,q(output)) 

			);

		} else { # we use track width

			$chain_ids[0] =~ /(\d+)/;
 			my $n = $1;
 			$debug and print "found chain id: $n\n";
			$format = signal_format(
						$devices{jack}->{signal_format},	
						$ti[$n]->ch_count
			);
		}
		push  @input_chains, 
			"-a:"
			. join(",",@chain_ids)
			. " -f:$format -i:jack_auto,$client";
	}
		
	##### Setting files as inputs (used by mon_setup)

	for my $full_path (keys %{ $inputs{file} } ) {
		
		$debug and print "monitor input file: $full_path\n";
		my $chain_ids = join ",",@{ $inputs{file}->{$full_path} };
		my ($chain) = $chain_ids =~ m/(\d+)/;
		$debug and print "input chain: $chain\n";
		push @input_chains, join ( " ",
					"-a:".$chain_ids,
			 		"-i:".  $Audio::Ecasound::Multitrack::ti[$chain]->modifiers .  $full_path);
 	}

	### Setting loops as inputs 

	for my $bus( @buses ){ # i.e. 'mixed', 'cooked'
		for my $loop ( keys %{ $inputs{$bus} }){
			push  @input_chains, 
			join " ", 
				"-a:" . (join ",", @{ $inputs{$bus}->{$loop} }),
				"-i:$loop";
		}
	}
	#####  Setting devices as outputs
	#
	for my $dev ( keys %{ $outputs{device} }){
			push @output_chains, join " ",
				"-a:" . (join "," , @{ $outputs{device}->{$dev} }),
				"-f:" . $devices{$dev}->{output_format},
				"-o:". $devices{$dev}->{ecasound_id}; }

	#####  Setting jack clients as outputs
 
	for my $client (keys %{ $outputs{jack} } ){

		my @chain_ids = @{ $outputs{jack}->{$client} };
		my $format;

		if ( $client eq 'system' ){ # we use the full soundcard width

			$format = signal_format(
				$devices{jack}->{signal_format},

				# client's input is our output
				jack_client($client,q(input))
			);

		} else { # we use track width

			$chain_ids[0] =~ /(\d+)/;
 			my $n = $1;
 			$debug and print "found chain id: $n\n";
			$format = signal_format(
						$devices{jack}->{signal_format},	
						$ti[$n]->ch_count
	 		);
		}
		push  @output_chains, 
			"-a:"
			. join(",",@chain_ids)
			. " -f:$format -o:jack_auto,$client";
	}
		
	### Setting loops as outputs 

	for my $bus( @buses ){ # i.e. 'mixed', 'cooked'
		for my $loop ( keys %{ $outputs{$bus} }){
			push  @output_chains, 
			join " ", 
				"-a:" . (join ",", @{ $outputs{$bus}->{$loop} }),
				"-o:$loop";
		}
	}
	##### Setting files as outputs (used by rec_file and mix)

	for my $key ( keys %{ $outputs{file} } ){
		my ($full_path, $format) = split " ", $key;
		$debug and print "record output file: $full_path\n";
		my $chain_ids = join ",",@{ $outputs{file}->{$key} };
		
		push @output_chains, join ( " ",
			 "-a:".$chain_ids,
			 "-f:".$format,
			 "-o:".$full_path,
		 );
			 
			 
	}

	## write general options
	
	my $ecs_file = "# ecasound chainsetup file\n\n";
	$ecs_file   .= "# general\n\n";
	$ecs_file   .= "$ecasound_globals\n\n";
	$ecs_file   .= "# audio inputs\n\n";
	$ecs_file   .= join "\n", sort @input_chains;
	$ecs_file   .= "\n\n# post-input processing\n\n";
	$ecs_file   .= join "\n", sort map{ "-a:$_ $post_input{$_}"} keys %post_input;
	$ecs_file   .= "\n\n# pre-output processing\n\n";
	$ecs_file   .= join "\n", sort map{ "-a:$_ $pre_output{$_}"} keys %pre_output;
	$ecs_file   .= "\n\n# audio outputs";
	$ecs_file   .= join "\n", sort @output_chains, "\n";
	
	$debug and print "ECS:\n",$ecs_file;
	my $sf = join_path(&project_dir, $chain_setup_file);
	open ECS, ">$sf" or croak "can't open file $sf:  $!\n";
	print ECS $ecs_file;
	close ECS;


	# write .ewf files
	#
	#map{ $_->write_ewf  } Audio::Ecasound::Multitrack::Track::all();
	
}

sub signal_format {
	my ($template, $channel_count) = @_;
	$template =~ s/N/$channel_count/;
	my $format = $template;
}

## transport functions

sub load_ecs {
		my $project_file = join_path(&project_dir , $chain_setup_file);
		eval_iam("cs-disconnect") if eval_iam("cs-connected");
		eval_iam"cs-remove" if eval_iam"cs-selected";
		eval_iam("cs-load ". $project_file);
		$debug and map{print "$_\n\n"}map{$e->eci($_)} qw(cs es fs st ctrl-status);
}
sub new_engine { 
	my $ecasound  = $ENV{ECASOUND} ? $ENV{ECASOUND} : q(ecasound);
	#print "ecasound name: $ecasound\n";
	system qq(killall $ecasound);
	sleep 1;
	system qq(killall -9 $ecasound);
	$e = Audio::Ecasound->new();
}
sub generate_setup { # create chain setup
	$debug2 and print "&generate_setup\n";
	%inputs = %outputs 
			= %post_input 
			= %pre_output 
			= @input_chains 
			= @output_chains 
			= ();
	

	# doodle mode
	# exclude tracks sharing inputs with previous tracks
	if ( $unique_inputs_only ){
		my @user = $tracker->tracks; # track names
		%excluded = ();
		my %already_used;
		map{ my $source = $tn{$_}->source; 
			if( $already_used{$source}  ){
				$excluded{$_} = $tn{$_}->rec_status();
			}
			$already_used{$source}++
		 } @user;
		if ( keys %excluded ){
			print "Multiple tracks share same inputs.\n";
			print "Excluding the following tracks: ", 
				join(" ", keys %excluded), "\n";
			map{ $tn{$_}->set(rw => 'OFF') } keys %excluded;
		}
	}
		
	my @tracks = Audio::Ecasound::Multitrack::Track::all;
	shift @tracks; # drop Master

	
	my $have_source = join " ", map{$_->name} 
								grep{ $_ -> rec_status ne 'OFF'} 
								@tracks;
	#print "have source: $have_source\n";
	if ($have_source) {
		$mixdown_bus->apply; # mix_file
		$master_bus->apply; # mix_out, mix_link
		$tracker_bus->apply;
		$null_bus->apply;
		map{ eliminate_loops($_) } all_chains();
		#print "minus loops\n \%inputs\n================\n", yaml_out(\%inputs);
		#print "\%outputs\n================\n", yaml_out(\%outputs);
		write_chains();
		return 1;
	} else { print "No inputs found!\n";
	return 0};
}
sub arm {
	if ( $preview ){
		stop_transport() ;
		print "Exiting preview/doodle mode\n" if $preview;
		$preview = 0;
		$rec_file->set(status => 1);
		$mon_setup->set(status => 1);
		my @excluded = keys %excluded;
		if ( @excluded ){
			print "Re-enabling the following tracks: @excluded\n";
			map{ $tn{$_}->set(rw => $excluded{$_}) } @excluded;
		}
		$unique_inputs_only = 0;
	}
	generate_setup() and connect_transport(); 
}
sub preview {
	return if transport_running();
	print "Starting engine in preview mode, WAV recording DISABLED.\n";
	$preview = 1;
	$rec_file->set(status => 0);
	generate_setup() and connect_transport();
	start_transport();
}
sub doodle {
	return if transport_running();
	print "Starting engine in doodle mode. Live inputs only.\n";
	$preview = 1;
	$rec_file->set(status => 0);
	$mon_setup->set(status => 0);
	$unique_inputs_only = 1;
	generate_setup() and connect_transport();
	start_transport();
}
sub connect_transport {
	load_ecs(); 
	eval_iam("cs-selected") and	eval_iam("cs-is-valid")
		or print("Invalid chain setup, engine not ready.\n"),return;
	find_op_offsets(); 
	apply_ops();
	eval_iam('cs-connect');
	my $status = eval_iam("engine-status");
	if ($status ne 'not started'){
		print("Invalid chain setup, cannot connect engine.\n");
		return;
	}
	eval_iam('engine-launch');
	$status = eval_iam("engine-status");
	if ($status ne 'stopped'){
		print "Failed to launch engine. Engine status: $status\n";
		return;
	}
	$length = eval_iam('cs-get-length'); 
	$ui->length_display(-text => colonize($length));
	# eval_iam("cs-set-length $length") unless @record;
	$ui->clock_config(-text => colonize(0));
	transport_status();
	$ui->flash_ready();
	#print eval_iam("fs");
	
}

sub transport_status {
	my $start  = Audio::Ecasound::Multitrack::Mark::loop_start();
	my $end    = Audio::Ecasound::Multitrack::Mark::loop_end();
	#print "start: $start, end: $end, loop_enable: $loop_enable\n";
	if ($loop_enable and $start and $end){
		#if (! $end){  $end = $start; $start = 0}
		print "looping from ", d1($start), 
			($start > 120 
				? " (" . colonize( $start ) . ") "  
				: " " ),
						"to ", d1($end),
			($end > 120 
				? " (".colonize( $end ). ") " 
				: " " ),
				$/;
	}
	print "setup length is ", d1($length), 
		($length > 120	?  " (" . colonize($length). ")" : "" )
		,$/;
	print "now at ", colonize( eval_iam( "getpos" )), $/;
	print "engine is ", eval_iam("engine-status"), $/;
}
sub start_transport { 
	$debug2 and print "&start_transport\n";
	carp("Invalid chain setup, aborting start.\n"),return unless eval_iam("cs-is-valid");

	print "starting at ", colonize(int (eval_iam"getpos")), $/;
	schedule_wraparound();
	eval_iam('start');
	sleep 1;
	$ui->start_heartbeat();

	sleep 1; # time for engine
	print "engine is ", eval_iam("engine-status"), $/;
}
sub heartbeat {
#	print "heartbeat fired\n";

	my $here   = eval_iam("getpos");
	my $status = eval_iam('engine-status');
	$ui->stop_heartbeat
		#if $status =~ /finished|error|stopped/;
		if $status =~ /finished|error/;
	#print join " ", $status, colonize($here), $/;
	my ($start, $end);
	$start  = Audio::Ecasound::Multitrack::Mark::loop_start();
	$end    = Audio::Ecasound::Multitrack::Mark::loop_end();
	$ui->schedule_wraparound() 
		if $loop_enable 
		and defined $start 
		and defined $end 
		and ! really_recording();

	# update time display
	#
	$ui->clock_config(-text => colonize(eval_iam('cs-get-position')));

}

sub schedule_wraparound {
	return unless $loop_enable;
	my $here   = eval_iam("getpos");
	my $start  = Audio::Ecasound::Multitrack::Mark::loop_start();
	my $end    = Audio::Ecasound::Multitrack::Mark::loop_end();
	my $diff = $end - $here;
	$debug and print "here: $here, start: $start, end: $end, diff: $diff\n";
	if ( $diff < 0 ){ # go at once
		eval_iam("setpos ".$start);
		$ui->cancel_wraparound();
	} elsif ( $diff < 3 ) { #schedule the move
	$ui->wraparound($diff, $start);
		
		;
	}
}
sub stop_transport { 
	$debug2 and print "&stop_transport\n"; 
	$ui->stop_heartbeat();
	eval_iam('stop');	
	print "engine is ", eval_iam("engine-status"), $/;
	$ui->project_label_configure(-background => $old_bg);
	sleeper(200_000);
	rec_cleanup();
}
sub transport_running {
#	$debug2 and print "&transport_running\n";
	 eval_iam('engine-status') eq 'running' ;
}
sub disconnect_transport {
	return if transport_running();
		eval_iam("cs-disconnect") if eval_iam("cs-connected");
}


sub toggle_unit {
	if ($unit == 1){
		$unit = 60;
		
	} else{ $unit = 1; }
}
sub show_unit { $time_step->configure(
	-text => ($unit == 1 ? 'Sec' : 'Min') 
)}

sub drop_mark {
	$debug2 and print "drop_mark()\n";
	my $name = shift;
	my $here = eval_iam("cs-get-position");

	print("mark exists already\n"), return 
		if grep { $_->time == $here } Audio::Ecasound::Multitrack::Mark::all();

	my $mark = Audio::Ecasound::Multitrack::Mark->new( time => $here, 
							name => $name);

		$ui->marker($mark); # for GUI
}
sub mark {
	$debug2 and print "mark()\n";
	my $mark = shift;
	my $pos = $mark->time;
	if ($markers_armed){ 
			$ui->destroy_marker($pos);
			$mark->remove;
		    arm_mark_toggle(); # disarm
	}
	else{ 

		set_position($pos);
	}
}

# TEXT routines


sub next_mark {
	my $jumps = shift;
	$jumps and $jumps--;
	my $here = eval_iam("cs-get-position");
	my @marks = sort { $a->time <=> $b->time } @Audio::Ecasound::Multitrack::Mark::all;
	for my $i ( 0..$#marks ){
		if ($marks[$i]->time - $here > 0.001 ){
			$debug and print "here: $here, future time: ",
			$marks[$i]->time, $/;
			eval_iam("setpos " .  $marks[$i+$jumps]->time);
			$this_mark = $marks[$i];
			return;
		}
	}
}
sub previous_mark {
	my $jumps = shift;
	$jumps and $jumps--;
	my $here = eval_iam("cs-get-position");
	my @marks = sort { $a->time <=> $b->time } @Audio::Ecasound::Multitrack::Mark::all;
	for my $i ( reverse 0..$#marks ){
		if ($marks[$i]->time < $here ){
			eval_iam("setpos " .  $marks[$i+$jumps]->time);
			$this_mark = $marks[$i];
			return;
		}
	}
}
	

## clock and clock-refresh functions ##
#

## jump recording head position

sub to_start { 
	return if really_recording();
	set_position( 0 );
}
sub to_end { 
	# ten seconds shy of end
	return if really_recording();
	my $end = eval_iam(qq(cs-get-length)) - 10 ;  
	set_position( $end);
} 
sub jump {
	return if really_recording();
	my $delta = shift;
	$debug2 and print "&jump\n";
	my $here = eval_iam('getpos');
	$debug and print "delta: $delta\nhere: $here\nunit: $unit\n\n";
	my $new_pos = $here + $delta * $unit;
	$new_pos = $new_pos < $length ? $new_pos : $length - 10;
	set_position( $new_pos );
	sleeper( 100_000 );
}
## post-recording functions

sub rememoize {
	return unless $memoize;
	package Audio::Ecasound::Multitrack::Wav;
	unmemoize('candidates');
	memoize(  'candidates');
}

sub rec_cleanup {  
	$debug2 and print "&rec_cleanup\n";
	print("transport still running, can't cleanup"),return if transport_running();
 	my @k = really_recording();
	$debug and print "intended recordings: " , join $/, @k;
	return unless @k;
	print "I was recording!\n";
	my $recorded = 0;
 	for my $k (@k) {    
 		my ($n) = $outputs{file}{$k}[-1] =~ m/(\d+)/; 
		print "k: $k, n: $n\n";
		my $file = $k;
		$file =~ s/ .*$//;
 		my $test_wav = $file;
		$debug and print "track: $n, file: $test_wav\n";
 		my ($v) = ($test_wav =~ /_(\d+)\.wav$/); 
		$debug and print "n: $n\nv: $v\n";
		$debug and print "testing for $test_wav\n";
		if (-e $test_wav) {
			$debug and print "exists. ";
			if (-s $test_wav > 44100) { # 0.5s x 16 bits x 44100/s
				$debug and print "bigger than a breadbox.  \n";
				$ti[$n]->set(active => undef); 
				$ui->update_version_button($n, $v);
			$recorded++;
			}
			else { unlink $test_wav }
		}
	}
	rememoize();
	my $mixed = scalar ( grep{ /\bmix*.wav/i} @k );
	
	$debug and print "recorded: $recorded mixed: $mixed\n";
	if ( ($recorded -  $mixed) >= 1) {
			# i.e. there are first time recorded tracks
			$ui->global_version_buttons(); # recreate
			$tracker->set( rw => 'MON');
			generate_setup() and connect_transport();
			$ui->refresh();
			print <<REC;
WAV files were recorded! Setting group to MON mode. 
Issue 'start' to review your recording.

REC
	}
		
} 
## effect functions
sub add_effect {
	
	$debug2 and print "&add_effect\n";
	
	my %p 			= %{shift()};
	my $n 			= $p{chain};
	my $code 			= $p{type};

	my $parent_id = $p{parent_id};  
	my $id		= $p{cop_id};   # initiates restore
	my $parameter		= $p{parameter};  # for controllers
	my $i = $effect_i{$code};
	my $values = $p{values};

	return if $id eq $ti[$n]->vol or
	          $id eq $ti[$n]->pan;   # skip these effects 
			   								# already created in add_track

	$id = cop_add(\%p); 
	my %pp = ( %p, cop_id => $id); # replace chainop id
	$ui->add_effect_gui(\%pp);
	apply_op($id) if eval_iam("cs-is-valid");

}

sub remove_effect {
	@_ = discard_object(@_);
	$debug2 and print "&remove_effect\n";
	my $id = shift;
	carp("$id: does not exist, skipping...\n"), return unless $cops{$id};
	my $n = $cops{$id}->{chain};
		
	my $parent = $cops{$id}->{belongs_to} ;
	print "id: $id, parent: $parent\n";

	my $object = $parent ? q(controller) : q(chain operator); 
	$debug and print qq(ready to remove $object "$id" from track "$n"\n);

	$ui->remove_effect_gui($id);

		# recursively remove children
		$debug and print "children found: ", join "|",@{$cops{$id}->{owns}},"\n";
		map{remove_effect($_)}@{ $cops{$id}->{owns} } 
			if defined $cops{$id}->{owns};
;
	 	# remove id from track object

		$ti[$n]->remove_effect( $id ); 

	if ( ! $parent ) { # i am a chain operator, have no parent
		remove_op($id);



	} else {  # i am a controller

	# remove the controller
 			
 		remove_op($id);

	# i remove ownership of deleted controller

		$debug and print "parent $parent owns list: ", join " ",
			@{ $cops{$parent}->{owns} }, "\n";

		@{ $cops{$parent}->{owns} }  =  grep{ $_ ne $id}
			@{ $cops{$parent}->{owns} } ; 
		$cops{$id}->{belongs_to} = undef;
		$debug and print "parent $parent new owns list: ", join " ",
			@{ $cops{$parent}->{owns} } ,$/;

	}
	delete $cops{$id}; # remove entry from chain operator list
	delete $copp{$id}; # remove entry from chain operator parameters list
}

sub remove_effect_gui { 
	@_ = discard_object(@_);
	$debug2 and print "&remove_effect_gui\n";
	my $id = shift;
	my $n = $cops{$id}->{chain};
	$debug and print "id: $id, chain: $n\n";

	$debug and print "i have widgets for these ids: ", join " ",keys %effects_widget, "\n";
	$debug and print "preparing to destroy: $id\n";
	$effects_widget{$id}->destroy();
	delete $effects_widget{$id}; 

}

sub nama_effect_index { # returns nama chain operator index
						# does not distinguish op/ctrl
	my $id = shift;
	my $n = $cops{$id}->{chain};
	$debug and print "id: $id n: $n \n";
	$debug and print join $/,@{ $ti[$n]->ops }, $/;
		for my $pos ( 0.. scalar @{ $ti[$n]->ops } - 1  ) {
			return $pos if $ti[$n]->ops->[$pos] eq $id; 
		};
}
sub ecasound_effect_index { 
	my $id = shift;
	my $n = $cops{$id}->{chain};
	my $opcount;  # one-based
	$debug and print "id: $id n: $n \n",join $/,@{ $ti[$n]->ops }, $/;
	for my $op (@{ $ti[$n]->ops }) { 
			# increment only for ops, not controllers
			next if $cops{$op}->{belongs_to};
			++$opcount;
			last if $op eq $id
	} 
	$ti[$n]->offset + $opcount;
}



sub remove_op {

	$debug2 and print "&remove_op\n";
	return unless eval_iam('cs-is-valid');
	my $id = shift;
	my $n = $cops{$id}->{chain};
	my $index;
	my $parent = $cops{$id}->{belongs_to}; 

	# select chain
	
	my $cmd = "c-select $n";
	$debug and print "cmd: $cmd$/";
	eval_iam($cmd);
	print "selected chain: ", eval_iam("c-selected"), $/; 

	# deal separately with controllers and chain operators

	if ( !  $parent ){ # chain operator
		$debug and print "no parent, assuming chain operator\n";
	
		$index = ecasound_effect_index( $id );
		$debug and print "ops list for chain $n: @{$ti[$n]->ops}\n";
		$debug and print "operator id to remove: $id\n";
		$debug and print "ready to remove from chain $n, operator id $id, index $index\n";
		$debug and print eval_iam("cs");
		eval_iam("cop-select ". ecasound_effect_index($id) );
		$debug and print "selected operator: ", eval_iam("cop-selected"), $/;
		eval_iam("cop-remove");
		$debug and print eval_iam("cs");

	} else { # controller

		$debug and print "has parent, assuming controller\n";

		my $ctrl_index = ctrl_index($id);
		$debug and print eval_iam("cs");
		eval_iam("cop-select ".  ecasound_effect_index(root_parent($id)));
		$debug and print "selected operator: ", eval_iam("cop-selected"), $/;
		eval_iam("ctrl-select $ctrl_index");
		eval_iam("ctrl-remove");
		$debug and print eval_iam("cs");
		$index = ctrl_index( $id );
		my $cmd = "c-select $n";
		#print "cmd: $cmd$/";
		eval_iam($cmd);
		# print "selected chain: ", eval_iam("c-selected"), $/; # Ecasound bug
		eval_iam("cop-select ". ($ti[$n]->offset + $index));
		#print "selected operator: ", eval_iam("cop-selected"), $/;
		eval_iam("cop-remove");
		$debug and eval_iam("cs");

	}
}


# Track sax effects: A B C GG HH II D E F
# GG HH and II are controllers applied to chain operator C
# 
# to remove controller HH:
#
# for Ecasound, chain op index = 3, 
#               ctrl index     = 2
#                              = nama_effect_index HH - nama_effect_index C 
#               
#
# for Nama, chain op array index 2, 
#           ctrl arrray index = chain op array index + ctrl_index
#                             = effect index - 1 + ctrl_index 
#
#

sub root_parent {
	my $id = shift;
	my $parent = $cops{$id}->{belongs_to};
	carp("$id: has no parent, skipping...\n"),return unless $parent;
	my $root_parent = $cops{$parent}->{belongs_to};
	$parent = $root_parent ? $root_parent : $parent;
	$debug and print "$id: is a controller-controller, root parent: $parent\n";
	$parent;
}

sub ctrl_index { 
	my $id = shift;

	nama_effect_index($id) - nama_effect_index(root_parent($id));

}
sub cop_add {
	my %p 			= %{shift()};
	my $n 			= $p{chain};
	my $code		= $p{type};
	my $parent_id = $p{parent_id};  
	my $id		= $p{cop_id};   # causes restore behavior when present
	my $i       = $effect_i{$code};
	my @values = @{ $p{values} } if $p{values};
	my $parameter	= $p{parameter};  # needed for parameter controllers
	                                  # zero based
	$debug2 and print "&cop_add\n";
$debug and print <<PP;
n:          $n
code:       $code
parent_id:  $parent_id
cop_id:     $id
effect_i:   $i
parameter:  $parameter
PP

	return $id if $id; # do nothing if cop_id has been issued

	# make entry in %cops with chain, code, display-type, children

	$debug and print "Issuing a new cop_id for track $n: $cop_id\n";
	# from the cop_id, we may also need to know chain number and effect

	$cops{$cop_id} = {chain => $n, 
					  type => $code,
					  display => $effects[$i]->{display},
					  owns => [] }; # DEBUGGIN TEST

	$p{cop_id} = $cop_id;
 	cop_init( \%p );

	if ($parent_id) {
		$debug and print "parent found: $parent_id\n";

		# store relationship
		$debug and print "parent owns" , join " ",@{ $cops{$parent_id}->{owns}}, "\n";

		push @{ $cops{$parent_id}->{owns}}, $cop_id;
		$debug and print join " ", "my attributes:", (keys %{ $cops{$cop_id} }), "\n";
		$cops{$cop_id}->{belongs_to} = $parent_id;
		$debug and print join " ", "my attributes again:", (keys %{ $cops{$cop_id} }), "\n";
		$debug and print "parameter: $parameter\n";

		# set fx-param to the parameter number, which one
		# above the zero-based array offset that $parameter represents
		
		$copp{$cop_id}->[0] = $parameter + 1; 
		
 		# find position of parent and insert child immediately afterwards

 		my $end = scalar @{ $ti[$n]->ops } - 1 ; 
 		for my $i (0..$end){
 			splice ( @{$ti[$n]->ops}, $i+1, 0, $cop_id ), last
 				if $ti[$n]->ops->[$i] eq $parent_id 
 		}
	}
	else { push @{$ti[$n]->ops }, $cop_id; } 

	# set values if present
	
	$copp{$cop_id} = \@values if @values; # needed for text mode

	$cop_id++; # return value then increment
}

sub cop_init {
	
	$debug2 and print "&cop_init\n";
	my $p = shift;
	my %p = %$p;
	my $id = $p{cop_id};
	my $parent_id = $p{parent_id};
	my $vals_ref  = $p{vals_ref};
	
	$debug and print "cop__id: $id\n";

	my @vals;
	if (ref $vals_ref) {
		@vals = @{ $vals_ref };
		$debug and print ("values supplied\n");
		@{ $copp{$id} } = @vals;
		return;
	} 
	else { 
		$debug and print "no settings found, loading defaults if present\n";
		my $i = $effect_i{ $cops{$id}->{type} };
		
		# don't initialize first parameter if operator has a parent
		# i.e. if operator is a controller
		
		for my $p ($parent_id ? 1 : 0..$effects[$i]->{count} - 1) {
		
			my $default = $effects[$i]->{params}->[$p]->{default};
			push @vals, $default;
		}
		@{ $copp{$id} } = @vals;
		$debug and print "copid: $id defaults: @vals \n";
	}
}

sub sync_effect_param {
	my ($id, $param) = @_;

	effect_update( $cops{$id}{chain}, 
					$id, 
					$param, 
					$copp{$id}[$param]	 );
}

sub effect_update_copp_set {

	my ($chain, $id, $param, $val) = @_;
	effect_update( @_ );
	$copp{$id}->[$param] = $val;
}
	
	
sub effect_update {
	
	# why not use this routine to update %copp values as
	# well?
	
	my $es = eval_iam"engine-status";
	$debug and print "engine is $es\n";
	return if $es !~ /not started|stopped|running/;

	my ($chain, $id, $param, $val) = @_;

	#print "chain $chain id $id param $param value $val\n";

	# $param gets incremented, therefore is zero-based. 
	# if I check i will find %copp is  zero-based

	$debug2 and print "&effect_update\n";
	return if $ti[$chain]->rec_status eq "OFF"; 
	return if $ti[$chain]->name eq 'Mixdown' and 
			  $ti[$chain]->rec_status eq 'REC';
 	$debug and print join " ", @_, "\n";	

	# update Ecasound's copy of the parameter

	$debug and print "valid: ", eval_iam("cs-is-valid"), "\n";
	my $controller; 
	for my $op (0..scalar @{ $ti[$chain]->ops } - 1) {
		$ti[$chain]->ops->[$op] eq $id and $controller = $op;
	}
	$param++; # so the value at $p[0] is applied to parameter 1
	$controller++; # translates 0th to chain-operator 1
	$debug and print 
	"cop_id $id:  track: $chain, controller: $controller, offset: ",
	$ti[$chain]->offset, " param: $param, value: $val$/";
	eval_iam("c-select $chain");
	eval_iam("cop-select ". ($ti[$chain]->offset + $controller));
	eval_iam("copp-select $param");
	eval_iam("copp-set $val");
}
sub find_op_offsets {

	
	$debug2 and print "&find_op_offsets\n";
	eval_iam('c-select-all');
		#my @op_offsets = split "\n",eval_iam("cs");
		my @op_offsets = grep{ /"\d+"/} split "\n",eval_iam("cs");
		shift @op_offsets; # remove comment line
		$debug and print join "\n\n",@op_offsets; 
		for my $output (@op_offsets){
			my $chain_id;
			($chain_id) = $output =~ m/Chain "(\w*\d+)"/;
			# print "chain_id: $chain_id\n";
			next if $chain_id =~ m/\D/; # skip id's containing non-digits
										# i.e. M1
			my $quotes = $output =~ tr/"//;
			$debug and print "offset: $quotes in $output\n"; 
			$ti[$chain_id]->set( offset => $quotes/2 - 1);  

		}
}
sub apply_ops {  # in addition to operators in .ecs file
	
	$debug2 and print "&apply_ops\n";
	my $last = scalar @Audio::Ecasound::Multitrack::Track::by_index - 1;
	$debug and print "looping over 1 to $last\n";
	for my $n (1..$last) {
	$debug and print "chain: $n, offset: ", $ti[$n]->offset, "\n";
 		next if $ti[$n]->rec_status eq "OFF" ;
		#next if $n == 2; # no volume control for mix track
		#next if ! defined $ti[$n]->offset; # for MIX
 		#next if ! $ti[$n]->offset ;

	# controllers will follow ops, so safe to apply all in order
		for my $id ( @{ $ti[$n]->ops } ) {
		apply_op($id);
		}
	}
}
sub apply_op {
	$debug2 and print "&apply_op\n";
	
	my $id = shift;
	$debug and print "id: $id\n";
	my $code = $cops{$id}->{type};
	my $dad = $cops{$id}->{belongs_to};
	$debug and print "chain: $cops{$id}->{chain} type: $cops{$id}->{type}, code: $code\n";
	#  if code contains colon, then follow with comma (preset, LADSPA)
	#  if code contains no colon, then follow with colon (ecasound,  ctrl)
	
	$code = '-' . $code . ($code =~ /:/ ? q(,) : q(:) );
	my @vals = @{ $copp{$id} };
	$debug and print "values: @vals\n";

	# we start to build iam command

	my $add = $dad ? "ctrl-add " : "cop-add "; 
	
	$add .= $code . join ",", @vals;

	# if my parent has a parent then we need to append the -kx  operator

	$add .= " -kx" if $cops{$dad}->{belongs_to};
	$debug and print "operator:  ", $add, "\n";

	eval_iam("c-select $cops{$id}->{chain}") ;

	if ( $dad ) {
	eval_iam("cop-select " . ecasound_effect_index($dad));
	}

	eval_iam($add);
	$debug and print "children found: ", join ",", "|",@{$cops{$id}->{owns}},"|\n";
	my $ref = ref $cops{$id}->{owns} ;
	$ref =~ /ARRAY/ or croak "expected array";
	my @owns = @{ $cops{$id}->{owns} };
	$debug and print "owns: @owns\n";  
	#map{apply_op($_)} @owns;

}

sub prepare_command_dispatch {
	map{ 
		if (my $subtext = $commands{$_}->{sub}){ # to_start
			my @short = split " ", $commands{$_}->{short};
			my @keys = $_;
			push @keys, @short if @short;
			map { $dispatch{$_} = eval qq(sub{ $subtext() }) } @keys;
		}
	} keys %commands;
# regex languge
#
my $key = qr/\w+/;
my $someval = qr/[\w.+-]+/;
my $sign = qr/[+-]/;
my $op_id = qr/[A-Z]+/;
my $parameter = qr/\d+/;
my $value = qr/[\d\.eE+-]+/; # -1.5e-6
my $dd = qr/\d+/;
my $name = qr/[\w:]+/;
my $name2 = qr/[\w-]+/;
my $name3 = qr/\S+/;
}
	

sub prepare_effects_help {

	# presets
	map{	s/^.*? //; 				# remove initial number
					$_ .= "\n";				# add newline
					my ($id) = /(pn:\w+)/; 	# find id
					s/,/, /g;				# to help line breaks
					push @effects_help,    $_;  #store help

				}  split "\n",eval_iam("preset-register");

	# LADSPA
	my $label;
	map{ 

		if (  my ($_label) = /-(el:\w+)/  ){
				$label = $_label;
				s/^\s+/ /;				 # trim spaces 
				s/'//g;     			 # remove apostrophes
				$_ .="\n";               # add newline
				push @effects_help, $_;  # store help

		} else { 
				# replace leading number with LADSPA Unique ID
				s/^\d+/$ladspa_unique_id{$label}/;

				s/\s+$/ /;  			# remove trailing spaces
				substr($effects_help[-1],0,0) = $_; # join lines
				$effects_help[-1] =~ s/,/, /g; # 
				$effects_help[-1] =~ s/,\s+$//;
				
		}

	} reverse split "\n",eval_iam("ladspa-register");


#my @lines = reverse split "\n",eval_iam("ladspa-register");
#pager( scalar @lines, $/, join $/,@lines);
	
	#my @crg = map{s/^.*? -//; $_ .= "\n" }
	#			split "\n",eval_iam("control-register");
	#pager (@lrg, @prg); exit;
}


sub prepare_static_effects_data{
	
	$debug2 and print "&prepare_static_effects_data\n";

	my $effects_cache = join_path(&project_root, $effects_cache_file);

	#print "newplugins: ", new_plugins(), $/;
	if ($opts{r} or new_plugins()){ 

		unlink $effects_cache;
		print "Regenerating effects data cache\n";
	}
	# TODO  re-read effects data if user presets are
	# newer than cache

	if (-f $effects_cache and ! $opts{s}){  
		$debug and print "found effects cache: $effects_cache\n";
		assign_var($effects_cache, @effects_static_vars);
	} else {
		
		$debug and print "reading in effects data, please wait...\n";
		read_in_effects_data();  
		# cop-register, preset-register, ctrl-register, ladspa-register
		get_ladspa_hints();     
		integrate_ladspa_hints();
		integrate_cop_hints();
		sort_ladspa_effects();
		prepare_effects_help();
		serialize (
			-file => $effects_cache, 
			-vars => \@effects_static_vars,
			-class => 'Audio::Ecasound::Multitrack',
			-storable => 1 );
	}

	prepare_effect_index();
}
sub new_plugins {
	my $effects_cache = join_path(&project_root, $effects_cache_file);
	my $path = $ENV{LADSPA_PATH} ? $ENV{LADSPA_PATH} : q(/usr/lib/ladspa);
	
	my @filenames;
	for my $dir ( split ':', $path){
		opendir DIR, $dir or carp "failed to open directory $dir: $!\n";
		push @filenames,  map{"$dir/$_"} grep{ /.so$/ } readdir DIR;
		closedir DIR;
	}
	push @filenames, '/usr/local/share/ecasound/effect_presets',
                 '/usr/share/ecasound/effect_presets',
                 "$ENV{HOME}/.ecasound/effect_presets";
	my $effmod = modified($effects_cache);
	my $latest;
	map{ my $mod = modified($_);
		 $latest = $mod if $mod > $latest } @filenames;

	$latest > $effmod
}

sub modified {
	my $filename = shift;
	#print "file: $filename\n";
	my @s = stat $filename;
	$s[9];
}
sub prepare_effect_index {
	%effect_j = ();
# =comment
# 	my @ecasound_effects = qw(
# 		ev evp ezf eS ea eac eaw eal ec eca enm ei epp
# 		ezx eemb eemp eemt ef1 ef3 ef4 efa efb efc efh efi
# 		efl efr efs erc erm etc etd ete etf etl etm etp etr);
# 	map { $effect_j{$_} = $_ } @ecasound_effects;
# =cut
	map{ 
		my $code = $_;
		my ($short) = $code =~ /:(\w+)/;
		if ( $short ) { 
			if ($effect_j{$short}) { warn "name collision: $_\n" }
			else { $effect_j{$short} = $code }
		}else{ $effect_j{$code} = $code };
	} keys %effect_i;
	#print yaml_out \%effect_j;
}
sub extract_effects_data {
	my ($lower, $upper, $regex, $separator, @lines) = @_;
	carp ("incorrect number of lines ", join ' ',$upper-$lower,scalar @lines)
		if $lower + @lines - 1 != $upper;
	$debug and print"lower: $lower upper: $upper  separator: $separator\n";
	#$debug and print "lines: ". join "\n",@lines, "\n";
	$debug and print "regex: $regex\n";
	
	for (my $j = $lower; $j <= $upper; $j++) {
		my $line = shift @lines;
	
		$line =~ /$regex/ or carp("bad effect data line: $line\n"),next;
		my ($no, $name, $id, $rest) = ($1, $2, $3, $4);
		$debug and print "Number: $no Name: $name Code: $id Rest: $rest\n";
		my @p_names = split $separator,$rest; 
		map{s/'//g}@p_names; # remove leading and trailing q(') in ladspa strings
		$debug and print "Parameter names: @p_names\n";
		$effects[$j]={};
		$effects[$j]->{number} = $no;
		$effects[$j]->{code} = $id;
		$effects[$j]->{name} = $name;
		$effects[$j]->{count} = scalar @p_names;
		$effects[$j]->{params} = [];
		$effects[$j]->{display} = qq(field);
		map{ push @{$effects[$j]->{params}}, {name => $_} } @p_names
			if @p_names;
;
	}
}
sub sort_ladspa_effects {
	$debug2 and print "&sort_ladspa_effects\n";
#	print yaml_out(\%e_bound); 
	my $aa = $e_bound{ladspa}{a};
	my $zz = $e_bound{ladspa}{z};
#	print "start: $aa end $zz\n";
	map{push @ladspa_sorted, 0} ( 1 .. $aa ); # fills array slice [0..$aa-1]
	splice @ladspa_sorted, $aa, 0,
		 sort { $effects[$a]->{name} cmp $effects[$b]->{name} } ($aa .. $zz) ;
	$debug and print "sorted array length: ". scalar @ladspa_sorted, "\n";
}		
sub read_in_effects_data {
	
	$debug2 and print "&read_in_effects_data\n";

	my $lr = eval_iam("ladspa-register");

	#print $lr; 
	
	my @ladspa =  split "\n", $lr;
	
	# join the two lines of each entry
	my @lad = map { join " ", splice(@ladspa,0,2) } 1..@ladspa/2; 

	my @preset = grep {! /^\w*$/ } split "\n", eval_iam("preset-register");
	my @ctrl  = grep {! /^\w*$/ } split "\n", eval_iam("ctrl-register");
	my @cop = grep {! /^\w*$/ } split "\n", eval_iam("cop-register");

	$debug and print "found ", scalar @cop, " Ecasound chain operators\n";
	$debug and print "found ", scalar @preset, " Ecasound presets\n";
	$debug and print "found ", scalar @ctrl, " Ecasound controllers\n";
	$debug and print "found ", scalar @lad, " LADSPA effects\n";

	# index boundaries we need to make effects list and menus
	$e_bound{cop}{a}   = 1;
	$e_bound{cop}{z}   = @cop; # scalar
	$e_bound{ladspa}{a} = $e_bound{cop}{z} + 1;
	$e_bound{ladspa}{b} = $e_bound{cop}{z} + int(@lad/4);
	$e_bound{ladspa}{c} = $e_bound{cop}{z} + 2*int(@lad/4);
	$e_bound{ladspa}{d} = $e_bound{cop}{z} + 3*int(@lad/4);
	$e_bound{ladspa}{z} = $e_bound{cop}{z} + @lad;
	$e_bound{preset}{a} = $e_bound{ladspa}{z} + 1;
	$e_bound{preset}{b} = $e_bound{ladspa}{z} + int(@preset/2);
	$e_bound{preset}{z} = $e_bound{ladspa}{z} + @preset;
	$e_bound{ctrl}{a}   = $e_bound{preset}{z} + 1;
	$e_bound{ctrl}{z}   = $e_bound{preset}{z} + @ctrl;

	my $cop_re = qr/
		^(\d+) # number
		\.    # dot
		\s+   # spaces+
		(\w.+?) # name, starting with word-char,  non-greedy
		# (\w+) # name
		,\s*  # comma spaces* 
		-(\w+)    # cop_id 
		:?     # maybe colon (if parameters)
		(.*$)  # rest
	/x;

	my $preset_re = qr/
		^(\d+) # number
		\.    # dot
		\s+   # spaces+
		(\w+) # name
		,\s*  # comma spaces* 
		-(pn:\w+)    # preset_id 
		:?     # maybe colon (if parameters)
		(.*$)  # rest
	/x;

	my $ladspa_re = qr/
		^(\d+) # number
		\.    # dot
		\s+  # spaces
		(\w.+?) # name, starting with word-char,  non-greedy
		\s+     # spaces
		-(el:\w+),? # ladspa_id maybe followed by comma
		(.*$)        # rest
	/x;

	my $ctrl_re = qr/
		^(\d+) # number
		\.     # dot
		\s+    # spaces
		(\w.+?) # name, starting with word-char,  non-greedy
		,\s*    # comma, zero or more spaces
		-(k\w+):?    # ktrl_id maybe followed by colon
		(.*$)        # rest
	/x;

	extract_effects_data(
		$e_bound{cop}{a},
		$e_bound{cop}{z},
		$cop_re,
		q(','),
		@cop,
	);


	extract_effects_data(
		$e_bound{ladspa}{a},
		$e_bound{ladspa}{z},
		$ladspa_re,
		q(','),
		@lad,
	);

	extract_effects_data(
		$e_bound{preset}{a},
		$e_bound{preset}{z},
		$preset_re,
		q(,),
		@preset,
	);
	extract_effects_data(
		$e_bound{ctrl}{a},
		$e_bound{ctrl}{z},
		$ctrl_re,
		q(,),
		@ctrl,
	);



	for my $i (0..$#effects){
		 $effect_i{ $effects[$i]->{code} } = $i; 
		 $debug and print "i: $i code: $effects[$i]->{code} display: $effects[$i]->{display}\n";
	}

	$debug and print "\@effects\n======\n", yaml_out(\@effects); ; 
}

sub integrate_cop_hints {

	my @cop_hints = @{ yaml_in( $cop_hints_yml ) };
	for my $hashref ( @cop_hints ){
		#print "cop hints ref type is: ",ref $hashref, $/;
		my $code = $hashref->{code};
		$effects[ $effect_i{ $code } ] = $hashref;
	}
}
sub get_ladspa_hints{
	$debug2 and print "&get_ladspa_hints\n";
	$ENV{LADSPA_PATH} or local $ENV{LADSPA_PATH}='/usr/lib/ladspa';
	my @dirs =  split ':', $ENV{LADSPA_PATH};
	my $data = '';
	my %seen = ();
	my @plugins;
	for my $dir (@dirs) {
		opendir DIR, $dir or carp qq(can't open LADSPA dir "$dir" for read: $!\n);
	
		push @plugins,  
			grep{ /\.so$/ and ! $seen{$_} and ++$seen{$_}} readdir DIR;
		closedir DIR;
	};
	#pager join $/, @plugins;

	# use these regexes to snarf data
	
	my $pluginre = qr/
	Plugin\ Name:       \s+ "([^"]+)" \s+
	Plugin\ Label:      \s+ "([^"]+)" \s+
	Plugin\ Unique\ ID: \s+ (\d+)     \s+
	[^\x00]+(?=Ports) 		# swallow maximum up to Ports
	Ports: \s+ ([^\x00]+) 	# swallow all
	/x;

	my $paramre = qr/
	"([^"]+)"   #  name inside quotes
	\s+
	(.+)        # rest
	/x;
		
	my $i;

	for my $file (@plugins){
		my @stanzas = split "\n\n", qx(analyseplugin $file);
		for my $stanza (@stanzas) {

			my ($plugin_name, $plugin_label, $plugin_unique_id, $ports)
			  = $stanza =~ /$pluginre/ 
				or carp "*** couldn't match plugin stanza $stanza ***";
			$debug and print "plugin label: $plugin_label $plugin_unique_id\n";

			my @lines = grep{ /input/ and /control/ } split "\n",$ports;

			my @params;  # data
			my @names;
			for my $p (@lines) {
				next if $p =~ /^\s*$/;
				$p =~ s/\.{3}/10/ if $p =~ /amplitude|gain/i;
				$p =~ s/\.{3}/60/ if $p =~ /delay|decay/i;
				$p =~ s(\.{3})($ladspa_sample_rate/2) if $p =~ /frequency/i;
				$p =~ /$paramre/;
				my ($name, $rest) = ($1, $2);
				my ($dir, $type, $range, $default, $hint) = 
					split /\s*,\s*/ , $rest, 5;
				$debug and print join( 
				"|",$name, $dir, $type, $range, $default, $hint) , $/; 
				#  if $hint =~ /logarithmic/;
				if ( $range =~ /toggled/i ){
					$range = q(0 to 1);
					$hint .= q(toggled);
				}
				my %p;
				$p{name} = $name;
				$p{dir} = $dir;
				$p{hint} = $hint;
				my ($beg, $end, $default_val, $resolution) 
					= range($name, $range, $default, $hint, $plugin_label);
				$p{begin} = $beg;
				$p{end} = $end;
				$p{default} = $default_val;
				$p{resolution} = $resolution;
				push @params, { %p };
			}

			$plugin_label = "el:" . $plugin_label;
			$ladspa_help{$plugin_label} = $stanza;
			$effects_ladspa_file{$plugin_unique_id} = $file;
			$ladspa_unique_id{$plugin_label} = $plugin_unique_id; 
			$ladspa_label{$plugin_unique_id} = $plugin_label;
			$effects_ladspa{$plugin_label}->{name}  = $plugin_name;
			$effects_ladspa{$plugin_label}->{id}    = $plugin_unique_id;
			$effects_ladspa{$plugin_label}->{params} = [ @params ];
			$effects_ladspa{$plugin_label}->{count} = scalar @params;
			$effects_ladspa{$plugin_label}->{display} = 'scale';
		}	#	pager( join "\n======\n", @stanzas);
		#last if ++$i > 10;
	}

	$debug and print yaml_out(\%effects_ladspa); 
}

sub srate_val {
	my $input = shift;
	my $val_re = qr/(
			[+-]? 			# optional sign
			\d+				# one or more digits
			(\.\d+)?	 	# optional decimal
			(e[+-]?\d+)?  	# optional exponent
	)/ix;					# case insensitive e/E
	my ($val) = $input =~ /$val_re/; #  or carp "no value found in input: $input\n";
	$val * ( $input =~ /srate/ ? $ladspa_sample_rate : 1 )
}
	
sub range {
	my ($name, $range, $default, $hint, $plugin_label) = @_; 
	my $multiplier = 1;;
	my ($beg, $end) = split /\s+to\s+/, $range;
	$beg = 		srate_val( $beg );
	$end = 		srate_val( $end );
	$default = 	srate_val( $default );
	$default = $default ? $default : $beg;
	$debug and print "beg: $beg, end: $end, default: $default\n";
	if ( $name =~ /gain|amplitude/i ){
		$beg = 0.01 unless $beg;
		$end = 0.01 unless $end;
	}
	my $resolution = ($end - $beg) / 100;
	if    ($hint =~ /integer|toggled/i ) { $resolution = 1; }
	elsif ($hint =~ /logarithmic/ ) {

		$beg = round ( log $beg ) if $beg;
		$end = round ( log $end ) if $end;
		$resolution = ($end - $beg) / 100;
		$default = $default ? round (log $default) : $default;
	}
	
	$resolution = d2( $resolution + 0.002) if $resolution < 1  and $resolution > 0.01;
	$resolution = dn ( $resolution, 3 ) if $resolution < 0.01;
	$resolution = int ($resolution + 0.1) if $resolution > 1 ;
	
	($beg, $end, $default, $resolution)

}
sub integrate_ladspa_hints {
	map{ 
		my $i = $effect_i{$_};
		# print ("$_ not found\n"), 
		if ($i) {
			$effects[$i]->{params} = $effects_ladspa{$_}->{params};
			# we revise the number of parameters read in from ladspa-register
			$effects[$i]->{count} = scalar @{$effects_ladspa{$_}->{params}};
			$effects[$i]->{display} = $effects_ladspa{$_}->{display};
		}
	} keys %effects_ladspa;

my %L;
my %M;

map { $L{$_}++ } keys %effects_ladspa;
map { $M{$_}++ } grep {/el:/} keys %effect_i;

for my $k (keys %L) {
	$M{$k} or $debug and print "$k not found in ecasound listing\n";
}
for my $k (keys %M) {
	$L{$k} or $debug and print "$k not found in ladspa listing\n";
}


$debug and print join "\n", sort keys %effects_ladspa;
$debug and print '-' x 60, "\n";
$debug and print join "\n", grep {/el:/} sort keys %effect_i;

#print yaml_out \@effects; exit;

}
sub d1 {
	my $n = shift;
	sprintf("%.1f", $n)
}
sub d2 {
	my $n = shift;
	sprintf("%.2f", $n)
}
sub dn {
	my ($n, $places) = @_;
	sprintf("%." . $places . "f", $n);
}
sub round {
	my $n = shift;
	return 0 if $n == 0;
	$n = int $n if $n > 10;
	$n = d2($n) if $n < 10;
	$n;
}
	

## persistent state support

sub save_state {
	$debug2 and print "&save_state\n";

	# first save palette to project_dir/palette.yml
	
	$ui->save_palette;

	# do nothing if only Master and Mixdown
	
	if (scalar @Audio::Ecasound::Multitrack::Track::by_index == 3 ){
		print "No user tracks, skipping...\n";
		return;
	}

	my $file = shift;

	# remove nulls in %cops 
	delete $cops{''};

	map{ 
		my $found; 
		$found = "yes" if defined $cops{$_}->{owns};
		$cops{$_}->{owns} = '~' unless $found;
	} keys %cops;

	# restore muted volume levels
	#
	my %muted;
	map{ $copp{ $ti[$_]->vol }->[0] = $old_vol{$_} ; 
		 $muted{$_}++;
	#	 $ui->paint_button($track_widget{$_}{mute}, q(brown) );
		} grep { $old_vol{$_} } all_chains();
	# TODO: old_vol should be incorporated into Track object
	# not separate variable
	#
	# (done for Text mode)

 # old vol level has been stored, thus is muted
 	
	$file = $file ? $file : $state_store_file;
	$file = join_path(&project_dir, $file) unless $file =~ m(/); 
	# print "filename base: $file\n";
	print "\nSaving state as $file.yml\n";

    # sort marks
	
	my @marks = sort keys %marks;
	%marks = ();
	map{ $marks{$_}++ } @marks;
	
# prepare tracks for storage

@tracks_data = (); # zero based, iterate over these to restore

map { push @tracks_data, $_->hashref } Audio::Ecasound::Multitrack::Track::all();

# print "found ", scalar @tracks_data, "tracks\n";

# prepare marks data for storage (new Mark objects)

@marks_data = ();
map { push @marks_data, $_->hashref } Audio::Ecasound::Multitrack::Mark::all();

@groups_data = ();
map { push @groups_data, $_->hashref } Audio::Ecasound::Multitrack::Group::all();

	serialize(
		-file => $file, 
		-vars => \@persistent_vars,
		-class => 'Audio::Ecasound::Multitrack',
	#	-storable => 1,
		);


# store alsa settings

	if ( $opts{a} ) {
		my $file = $file;
		$file =~ s/\.yml$//;
		print "storing ALSA settings\n";
		print qx(alsactl -f $file.alsa store);
	}
	# now remute
	
	map{ $copp{ $ti[$_]->vol }->[0] = 0} 
	grep { $muted{$_}} 
	all_chains();

	# restore %cops
	map{ $cops{$_}->{owns} eq '~' and $cops{$_}->{owns} = [] } keys %cops; 

}
sub assign_var {
	my ($source, @vars) = @_;
	assign_vars(
				-source => $source,
				-vars   => \@vars,
				-class => 'Audio::Ecasound::Multitrack');
}
sub retrieve_state {
	$debug2 and print "&retrieve_state\n";
	my $file = shift;
	$file = $file ? $file : $state_store_file;
	$file = join_path(project_dir(), $file);
	my $yamlfile = $file;
	$yamlfile .= ".yml" unless $yamlfile =~ /yml$/;
	$file = $yamlfile if -f $yamlfile;
	! -f $file and (print "file not found: $file.yml\n"), return;
	$debug and print "using file: $file\n";

	assign_var($file, @persistent_vars );

	##  print yaml_out \@groups_data; 
	# %cops: correct 'owns' null (from YAML) to empty array []
	
	map{ $cops{$_}->{owns} or $cops{$_}->{owns} = [] } keys %cops; 

	#  set group parameters

	map {my $g = $_; 
		map{
			$Audio::Ecasound::Multitrack::Group::by_index[$g->{n}]->set($_ => $g->{$_})
			} keys %{$g};
	} @groups_data;

	#  set Master and Mixdown parmeters
	


	map {my $t = $_; 
			my %track = %{$t};
		map{

			$Audio::Ecasound::Multitrack::Track::by_index[$t->{n}]->set($_ => $t->{$_})
			} keys %track;
	} @tracks_data[0,1];

	splice @tracks_data, 0, 2;

	$ui->create_master_and_mix_tracks(); 

	# create user tracks
	
	my $did_apply = 0;

	map{ 
		my %h = %$_; 
		#print "old n: $h{n}\n";
		#print "h: ", join " ", %h, $/;
		delete $h{n};
		#my @hh = %h; print "size: ", scalar @hh, $/;
		my $track = Audio::Ecasound::Multitrack::Track->new( %h ) ;
		my $n = $track->n;
		#print "new n: $n\n";
		$debug and print "restoring track: $n\n";
		$ui->track_gui($n); 
		
		for my $id (@{$ti[$n]->ops}){
			$did_apply++ 
				unless $id eq $ti[$n]->vol
					or $id eq $ti[$n]->pan;
			
			add_effect({
						chain => $cops{$id}->{chain},
						type => $cops{$id}->{type},
						cop_id => $id,
						parent_id => $cops{$id}->{belongs_to},
						});

		# TODO if parent has a parent, i am a parameter controller controlling
		# a parameter controller, and therefore need the -kx switch
		}
	} @tracks_data;
	#print "\n---\n", $tracker->dump;  
	#print "\n---\n", map{$_->dump} Audio::Ecasound::Multitrack::Track::all;# exit; 
	$did_apply and $ui->manifest;
	$debug and print join " ", 
		(map{ ref $_, $/ } @Audio::Ecasound::Multitrack::Track::by_index), $/;



	$ui->refresh_oids();

	# restore Alsa mixer settings
	if ( $opts{a} ) {
		my $file = $file; 
		$file =~ s/\.yml$//;
		print "restoring ALSA settings\n";
		print qx(alsactl -f $file.alsa restore);
	}

	# text mode marks 
		
	map{ 
		my %h = %$_; 
		my $mark = Audio::Ecasound::Multitrack::Mark->new( %h ) ;
	} @marks_data;
	$ui->restore_time_marks();

} 

sub save_effects {
	$debug2 and print "&save_effects\n";
	my $file = shift;
	
	# restore muted volume levels
	#
	my %muted;
	
	map  {$copp{ $ti[$_]->vol }->[0] = $old_vol{$_} ;
		  $ui->paint_button($track_widget{$_}{mute}, $old_bg ) }
	grep { $old_vol{$_} }  # old vol level stored and muted
	all_chains();

	# we need the ops list for each track
	#
	# i dont see why, do we overwrite the effects section
	# in one of the init routines?
	# I will follow for now 12/6/07
	
	%state_c_ops = ();
	map{ 	$state_c_ops{$_} = $ti[$_]->ops } all_chains();

	# map {remove_op} @{ $ti[$_]->ops }

	store_vars(
		-file => $file, 
		-vars => \@effects_dynamic_vars,
		-class => 'Audio::Ecasound::Multitrack');

}

sub process_control_inputs { }

sub set_position {
	my $seconds = shift;
	my $am_running = ( eval_iam('engine-status') eq 'running');
	return if really_recording();
	my $jack = $jack_running;
	#print "jack: $jack\n";
	$am_running and $jack and eval_iam('stop');
	eval_iam("setpos $seconds");
	$am_running and $jack and sleeper($seek_delay), eval_iam('start');
	$ui->clock_config(-text => colonize($seconds));
}

sub forward {
	my $delta = shift;
	my $here = eval_iam('getpos');
	my $new = $here + $delta;
	set_position( $new );
}

sub rewind {
	my $delta = shift;
	forward( -$delta );
}
sub mute {
	return if $this_track->old_vol_level();
	$this_track->set(old_vol_level => $copp{$this_track->vol}[0])
		if ( $copp{$this_track->vol}[0]);  # non-zero volume
	$copp{ $this_track->vol }->[0] = 0;
	sync_effect_param( $this_track->vol, 0);
}
sub unmute {
	return if $copp{$this_track->vol}[0]; # if we are not muted
	return if ! $this_track->old_vol_level;
	$copp{$this_track->vol}[0] = $this_track->old_vol_level;
	$this_track->set(old_vol_level => 0);
	sync_effect_param( $this_track->vol, 0);
}
sub solo {
	my $current_track = $this_track;
	if ($soloing) { all() }

	# get list of already muted tracks if I haven't done so already
	
	if ( ! @already_muted ){
	print "none muted\n";
		@already_muted = grep{ $_->old_vol_level} 
                         map{ $tn{$_} } 
						 $tracker->tracks;
	print join " ", "muted", map{$_->name} @already_muted;
	}

	# mute all tracks
	map { $this_track = $tn{$_}; mute() } $tracker->tracks;

    $this_track = $current_track;
    unmute();
	$soloing = 1;
}

sub all {
	
	my $current_track = $this_track;
	# unmute all tracks
	map { $this_track = $tn{$_}; unmute() } $tracker->tracks;

	# re-mute previously muted tracks
	if (@already_muted){
		map { $this_track = $_; mute() } @already_muted;
	}

	# remove listing of muted tracks
	
	@already_muted = ();
	$this_track = $current_track;
	$soloing = 0;
	
}

sub show_chain_setup {
	$debug2 and print "&show_chain_setup\n";
	my $setup = join_path( project_dir(), $chain_setup_file);
	if ( $use_pager ) {
		my $pager = $ENV{PAGER} ? $ENV{PAGER} : "/usr/bin/less";
		system qq($pager $setup);
	} else {
		my $chain_setup;
		io( $setup ) > $chain_setup; 
		print $chain_setup, $/;
	}
}
sub pager {
	$debug2 and print "&pager\n";
	my @output = @_;
	my ($screen_lines, $columns) = split " ", qx(stty size);
	my $line_count = 0;
	map{ $line_count += $_ =~ tr(\n)(\n) } @output;
	if ( $use_pager and $line_count > $screen_lines - 2) { 
		my $fh = File::Temp->new();
		my $fname = $fh->filename;
		print $fh @output;
		file_pager($fname);
	} else {
		print @output;
	}
	print "\n\n";
}
sub file_pager {
	$debug2 and print "&file_pager\n";
	my $fname = shift;
	if (! -e $fname or ! -r $fname ){
		carp "file not found or not readable: $fname\n" ;
		return;
    }
	my $pager = $ENV{PAGER} ? $ENV{PAGER} : "/usr/bin/less";
	my $cmd = qq($pager $fname); 
	system $cmd;
}
sub dump_all {
	my $tmp = ".dump_all";
	my $fname = join_path( project_root(), $tmp);
	save_state($fname);
	file_pager("$fname.yml");
}


sub show_io {
	my $output = yaml_out( \%inputs ). yaml_out( \%outputs ); 
	pager( $output );
}
sub get_ecasound_iam_keywords {

	my %reserved = map{ $_,1 } qw(  forward
									fw
									getpos
									h
									help
									rewind
									quit
									q
									rw
									s
									setpos
									start
									stop
									t
									?	);
	
	%iam_cmd = map{$_,1 } 
				grep{ ! $reserved{$_} } split " ", eval_iam('int-cmd-list');
}

sub process_line {
  $debug2 and print "&process_line\n";
  my ($user_input) = @_;
  $debug and print "user input: $user_input\n";

  if (defined $user_input and $user_input !~ /^\s*$/)
    {
    $term->addhistory($user_input) 
	 	unless $user_input eq $previous_text_command;
 	$previous_text_command = $user_input;
	command_process( $user_input );
    }
}


sub command_process {
	my ($user_input) = shift;
	return if $user_input =~ /^\s*$/;
	$debug and print "user input: $user_input\n";
	my ($cmd, $predicate) = ($user_input =~ /([\S]+)(.*)/);
	if ($cmd eq 'for' 
			and my ($bunchy, $do) = $predicate =~ /\s*(.+?)\s*;(.+)/){
		$debug and print "bunch: $bunchy do: $do\n";
		my @tracks;
		if ($bunchy =~ /\S \S/ or $tn{$bunchy} or $ti[$bunchy]){
			$debug and print "multiple tracks found\n";
			@tracks = split " ", $bunchy;
			$debug and print "multitracks: @tracks\n";
		} elsif ( lc $bunchy eq 'all' ){
			$debug and print "special bunch: all\n";
			@tracks = $tracker->tracks;
		} elsif ( @tracks = @{$bunch{$bunchy}}) {
			$debug and print "bunch tracks: @tracks\n";
 		}
		for my $t(@tracks) {
			command_process("$t; $do");
		}
	} elsif ($cmd eq 'eval') {
			$debug and print "Evaluating perl code\n";
			pager( eval $predicate );
			print "\n";
			$@ and print "Perl command failed: $@\n";
	}
	elsif ( $cmd eq '!' ) {
			$debug and print "Evaluating shell commands!\n";
			#system $predicate;
			my $output = qx( $predicate );
			#print "length: ", length $output, $/;
			pager($output); 
			print "\n";
	} else {


	my @user_input = split /\s*;\s*/, $user_input;
	map {
		my $user_input = $_;
		my ($cmd, $predicate) = ($user_input =~ /([\S]+)(.*)/);
		$debug and print "cmd: $cmd \npredicate: $predicate\n";
		if ($cmd eq 'eval') {
			$debug and print "Evaluating perl code\n";
			pager( eval $predicate);
			print "\n";
			$@ and print "Perl command failed: $@\n";
		} elsif ($cmd eq '!') {
			$debug and print "Evaluating shell commands!\n";
			my $output = qx( $predicate );
			#print "length: ", length $output, $/;
			pager($output); 
			print "\n";
		} elsif ($tn{$cmd}) { 
			$debug and print qq(Selecting track "$cmd"\n);
			$this_track = $tn{$cmd};
			my $c = q(c-select ) . $this_track->n; eval_iam( $c );
			$predicate !~ /^\s*$/ and $parser->command($predicate);
		} elsif ($cmd =~ /^\d+$/ and $ti[$cmd]) { 
			$debug and print qq(Selecting track ), $ti[$cmd]->name, $/;
			$this_track = $ti[$cmd];
			my $c = q(c-select ) . $this_track->n; eval_iam( $c );
			$predicate !~ /^\s*$/ and $parser->command($predicate);
		} elsif ($iam_cmd{$cmd}){
			$debug and print "Found Iam command\n";
			my $result = eval_iam($user_input);
			pager( $result );  
		} else {
			$debug and print "Passing to parser\n", $_, $/;
			#print 1, ref $parser, $/;
			#print 2, ref $Audio::Ecasound::Multitrack::parser, $/;
			# both print
			defined $parser->command($_) 
				or print "Bad command: $_\n";
		}    
	} @user_input;
	}
	$ui->refresh; # in case we have a graphic environment
}
sub load_keywords {

@keywords = keys %commands;
push @keywords, grep{$_} map{split " ", $commands{$_}->{short}} @keywords;
push @keywords, keys %iam_cmd;
push @keywords, keys %effect_j;
}

sub complete {
    my ($text, $line, $start, $end) = @_;
    return $term->completion_matches($text,\&keyword);
};

{
    my $i;
    sub keyword {
        my ($text, $state) = @_;
        return unless $text;
        if($state) {
            $i++;
        }
        else { # first call
            $i = 0;
        }
        for (; $i<=$#keywords; $i++) {
            return $keywords[$i] if $keywords[$i] =~ /^\Q$text/;
        };
        return undef;
    }
};
sub jack_client {

	# returns true if client and direction exist
	# returns number of client ports
	
	my ($name, $direction)  = @_;
	# synth:in_1 input
	# synth input
	my $j = qx(jack_lsp -Ap);

	# convert to single lines

	$j =~ s/\n\s+/ /sg;

	# system:capture_1 alsa_pcm:capture_1 properties: output,physical,terminal,

	my %jack;

	map{ 
		my ($direction) = /properties: (input|output)/;
		s/properties:.+//;
		my @ports = /(\w+:\w+ )/g;
		map { 
				s/ $//; # remove trailing space
				$jack{ $_ }{ $direction }++;
				my ($client, $port) = /(\w+):(\w+)/;
				$jack{ $client }{ $direction }++;

		 } @ports;

	} split "\n",$j;
	#print yaml_out \%jack;

	$jack{$name}{$direction};
}
	
### end


# gui handling
#
use Carp;

sub init_gui {

	$debug2 and print "&init_gui\n";

	@_ = discard_object(@_);

	init_palettefields();


### 	Tk root window 

	# Tk main window
 	$mw = MainWindow->new;  
	$set_event = $mw->Label();
	$mw->optionAdd('*font', 'Helvetica 12');
	$mw->title("Ecasound/Nama"); 
	$mw->deiconify;
	$parent{mw} = $mw;

	### init effect window

	$ew = $mw->Toplevel;
	$ew->title("Effect Window");
	$ew->deiconify; 
	$ew->withdraw;
	$parent{ew} = $ew;

	
	$canvas = $ew->Scrolled('Canvas')->pack;
	$canvas->configure(
		scrollregion =>[2,2,10000,2000],
		-width => 900,
		-height => 600,	
		);
# 		scrollregion =>[2,2,10000,2000],
# 		-width => 1000,
# 		-height => 4000,	
	$effect_frame = $canvas->Frame;
	my $id = $canvas->createWindow(30,30, -window => $effect_frame,
											-anchor => 'nw');

	$project_label = $mw->Label->pack(-fill => 'both');
	get_saved_colors();

	$time_frame = $mw->Frame(
	#	-borderwidth => 20,
	#	-relief => 'groove',
	)->pack(
		-side => 'bottom', 
		-fill => 'both',
	);
	$mark_frame = $time_frame->Frame->pack(
		-side => 'bottom', 
		-fill => 'both');
	$fast_frame = $time_frame->Frame->pack(
		-side => 'bottom', 
		-fill => 'both');
	$transport_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	#$oid_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	$clock_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	#$group_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	$track_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
 	#$group_label = $group_frame->Menubutton(-text => "GROUP",
 #										-tearoff => 0,
 #										-width => 13)->pack(-side => 'left');
		
	$add_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	$perl_eval_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	$iam_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	$load_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
#	my $blank = $mw->Label->pack(-side => 'left');



	$sn_label = $load_frame->Label(
		-text => "    Project name: "
	)->pack(-side => 'left');
	$sn_text = $load_frame->Entry(
		-textvariable => \$project,
		-width => 25
	)->pack(-side => 'left');
	$sn_load = $load_frame->Button->pack(-side => 'left');;
	$sn_new = $load_frame->Button->pack(-side => 'left');;
	$sn_quit = $load_frame->Button->pack(-side => 'left');
	$sn_save = $load_frame->Button->pack(-side => 'left');
	$save_id = "State";
	my $sn_save_text = $load_frame->Entry(
									-textvariable => \$save_id,
									-width => 15
									)->pack(-side => 'left');
	$sn_recall = $load_frame->Button->pack(-side => 'left');
	$sn_palette = $load_frame->Menubutton(-tearoff => 0)
		->pack( -side => 'left');
	$sn_namapalette = $load_frame->Menubutton(-tearoff => 0)
		->pack( -side => 'left');
	# $sn_dump = $load_frame->Button->pack(-side => 'left');

	$build_track_label = $add_frame->Label(
		-text => "New track name: ")->pack(-side => 'left');
	$build_track_text = $add_frame->Entry(
		-textvariable => \$track_name, 
		-width => 12
	)->pack(-side => 'left');
# 	$build_track_mon_label = $add_frame->Label(
# 		-text => "Aux send: (channel/client):",
# 		-width => 18
# 	)->pack(-side => 'left');
# 	$build_track_mon_text = $add_frame->Entry(
# 		-textvariable => \$ch_m, 
# 		-width => 10
# 	)->pack(-side => 'left');
	$build_track_rec_label = $add_frame->Label(
		-text => "Input channel or client:"
	)->pack(-side => 'left');
	$build_track_rec_text = $add_frame->Entry(
		-textvariable => \$ch_r, 
		-width => 10
	)->pack(-side => 'left');
	$build_track_add_mono = $add_frame->Button->pack(-side => 'left');;
	$build_track_add_stereo  = $add_frame->Button->pack(-side => 'left');;

	$sn_load->configure(
		-text => 'Load',
		-command => sub{ load_project(
			name => remove_spaces $project_name),
			});
	$sn_new->configure( 
		-text => 'Create',
		-command => sub{ load_project(
							name => remove_spaces($project_name),
							create => 1)});
	$sn_save->configure(
		-text => 'Save settings',
		-command => #sub { print "save_id: $save_id\n" });
		 sub {save_state($save_id) });
	$sn_recall->configure(
		-text => 'Recall settings',
 		-command => sub {load_project (name => $project_name, 
 										settings => $save_id)},
				);
	$sn_quit->configure(-text => "Quit",
		 -command => sub { 
				return if transport_running();
				save_state($save_id);
				print "Exiting... \n";		
				#$term->tkRunning(0);
				#$ew->destroy;
				#$mw->destroy;
				#Audio::Ecasound::Multitrack::Text::command_process('quit');
				exit;
				 });
# 	$sn_dump->configure(
# 		-text => q(Dump state),
# 		-command => sub{ print &status_vars });
	$sn_palette->configure(
		-text => 'Palette',
		-relief => 'raised',
	);
	$sn_namapalette->configure(
		-text => 'Nama Palette',
		-relief => 'raised',
	);

my @color_items = map { [ 'command' => $_, 
							-command  => colorset($_,$mw->cget("-$_") )]
						} @palettefields;
$sn_palette->AddItems( @color_items);

@color_items = map { [ 'command' => $_, 
						-command  => namaset($_, $namapalette{$_})]
						} @namafields;
$sn_namapalette->AddItems( @color_items);

	$build_track_add_mono->configure( 
			-text => 'Add Mono Track',
			-command => sub { 
					return if $track_name =~ /^\s*$/;	
			add_track(remove_spaces($track_name)) }
	);
	$build_track_add_stereo->configure( 
			-text => 'Add Stereo Track',
			-command => sub { 
								return if $track_name =~ /^\s*$/;	
								add_track(remove_spaces($track_name));
								Audio::Ecasound::Multitrack::Text::command_process('stereo');
	});

	my @labels = 
		qw(Track Name Version Status Source Send Volume Mute Unity Pan Center Effects);
	my @widgets;
	map{ push @widgets, $track_frame->Label(-text => $_)  } @labels;
	$widgets[0]->grid(@widgets[1..$#widgets]);

#  unified command processing by command_process 
	
	$iam_label = $iam_frame->Label(
	-text => "         Command: "
		)->pack(-side => 'left');;
	$iam_text = $iam_frame->Entry( 
		-textvariable => \$iam, -width => 45)
		->pack(-side => 'left');;
	$iam_execute = $iam_frame->Button(
			-text => 'Execute',
			-command => sub { Audio::Ecasound::Multitrack::Text::command_process( $iam ) }
			
		)->pack(-side => 'left');;

			#join  " ",
			# grep{ $_ !~ add fxa afx } split /\s*;\s*/, $iam) 
		
}

sub transport_gui {
	@_ = discard_object(@_);
	$debug2 and print "&transport_gui\n";

	$transport_label = $transport_frame->Label(
		-text => 'TRANSPORT',
		-width => 12,
		)->pack(-side => 'left');;
	$transport_setup_and_connect  = $transport_frame->Button->pack(-side => 'left');;
	$transport_start = $transport_frame->Button->pack(-side => 'left');
	$transport_stop = $transport_frame->Button->pack(-side => 'left');
	#$transport_setup = $transport_frame->Button->pack(-side => 'left');;
	#$transport_connect = $transport_frame->Button->pack(-side => 'left');;
	#$transport_disconnect = $transport_frame->Button->pack(-side => 'left');;
	# $transport_new = $transport_frame->Button->pack(-side => 'left');;

	$transport_stop->configure(-text => "Stop",
	-command => sub { 
					stop_transport();
				}
		);
	$transport_start->configure(
		-text => "Start",
		-command => sub { 
		return if transport_running();
		my $color = engine_mode_color();
		project_label_configure(-background => $color);
		start_transport();
				});
	$transport_setup_and_connect->configure(
			-text => 'Arm',
			-command => sub {arm()}
						 );

preview_button();

}
sub time_gui {
	@_ = discard_object(@_);
	$debug2 and print "&time_gui\n";

	my $time_label = $clock_frame->Label(
		-text => 'TIME', 
		-width => 12);
	#print "bg: $namapalette{ClockBackground}, fg:$namapalette{ClockForeground}\n";
	$clock = $clock_frame->Label(
		-text => '0:00', 
		-width => 8,
		-background => $namapalette{ClockBackground},
		-foreground => $namapalette{ClockForeground},
		);
	my $length_label = $clock_frame->Label(
		-text => 'LENGTH',
		-width => 10,
		);
	$setup_length = $clock_frame->Label(
	#	-width => 8,
		);

	for my $w ($time_label, $clock, $length_label, $setup_length) {
		$w->pack(-side => 'left');	
	}

	$mark_frame = $time_frame->Frame->pack(
		-side => 'bottom', 
		-fill => 'both');
	my $fast_frame = $time_frame->Frame->pack(
		-side => 'bottom', 
		-fill => 'both');
	# jump

	my $jump_label = $fast_frame->Label(-text => q(JUMP), -width => 12);
	my @pluses = (1, 5, 10, 30, 60);
	my @minuses = map{ - $_ } reverse @pluses;
	my @fw = map{ my $d = $_; $fast_frame->Button(
			-text => $d,
			-command => sub { jump($d) },
			)
		}  @pluses ;
	my @rew = map{ my $d = $_; $fast_frame->Button(
			-text => $d,
			-command => sub { jump($d) },
			)
		}  @minuses ;
	my $beg = $fast_frame->Button(
			-text => 'Beg',
			-command => \&to_start,
			);
	my $end = $fast_frame->Button(
			-text => 'End',
			-command => \&to_end,
			);

	$time_step = $fast_frame->Button( 
			-text => 'Sec',
			);
		for my $w($jump_label, @rew, $beg, $time_step, $end, @fw){
			$w->pack(-side => 'left')
		}

	$time_step->configure (-command => sub { &toggle_unit; &show_unit });

	# Marks
	
	my $mark_label = $mark_frame->Label(
		-text => q(MARK), 
		-width => 12,
		)->pack(-side => 'left');
		
	my $drop_mark = $mark_frame->Button(
		-text => 'Place',
		-command => \&drop_mark,
		)->pack(-side => 'left');	
		
	$mark_remove = $mark_frame->Button(
		-text => 'Remove',
		-command => \&arm_mark_toggle,
	)->pack(-side => 'left');	

}

#  the following is based on previous code for multiple buttons
#  needs cleanup

sub preview_button { 
	$debug2 and print "&preview\n";
	@_ = discard_object(@_);
	#my $outputs = $oid_frame->Label(-text => 'OUTPUTS', -width => 12);
	my @oid_name;
	for my $rule ( Audio::Ecasound::Multitrack::Rule::all_rules ){
		my $name = $rule->name;
		next unless $name eq 'rec_file'; # REC_FILE only!!!
		my $status = $rule->status;
		#print "gui oid name: $name status: $status\n";
		#next if $name =~ m/setup|mix_|mixer|rec_file|multi/i;
		push @oid_name, $name;
		
		my $oid_button = $transport_frame->Button( 
			# -text => ucfirst $name,
			-text => "Preview",
		);
		$oid_button->configure(
			-command => sub { 
				$rule->set(status => ! $rule->status);
				$oid_button->configure( 
			-background => 
					$rule->status ? $old_bg : $namapalette{Preview} ,
			-activebackground => 
					$rule->status ? $old_bg : $namapalette{ActivePreview} ,
			-text => 
					$rule->status ? 'Preview' : 
'PREVIEW MODE: Record WAV DISABLED. Press again to release.'
					
					);

			if ($rule->status) { # rec_file enabled
				arm()
			} else { 
				preview();
			}

			});
		push @widget_o, $oid_button;
	}
		
	map { $_ -> pack(-side => 'left') } (@widget_o);
	
}
sub paint_button {
	@_ = discard_object(@_);
	my ($button, $color) = @_;
	$button->configure(-background => $color,
						-activebackground => $color);
}

sub engine_mode_color {
		if ( user_rec_tracks()  ){ 
				$rec  					# live recording
		} elsif ( &really_recording ){ 
				$namapalette{Mixdown}	# mixdown only 
		} elsif ( user_mon_tracks() ){  
				$namapalette{Play}; 	# just playback
		} else { $old_bg } 
	}

sub flash_ready {

	my $color = engine_mode_color();
	$debug and print "flash color: $color\n";
	length_display(-background => $color);
	project_label_configure(-background => $color) unless $preview;
	$event_id{tk_flash_ready}->cancel() if defined $event_id{tk_flash_ready};
	$event_id{tk_flash_ready} = $set_event->after(3000, 
		sub{ length_display(-background => $old_bg);
			 project_label_configure(-background => 'antiquewhite') 
 }
	);
}
sub group_gui {  
	@_ = discard_object(@_);
	my $group = $tracker; 
	my $dummy = $track_frame->Label(-text => ' '); 
	$group_label = 	$track_frame->Label(
			-text => "G R O U P",
			-foreground => $namapalette{GroupForeground},
			-background => $namapalette{GroupBackground},

 );
	$group_version = $track_frame->Menubutton( 
		-text => q( ), 
		-tearoff => 0,
		-foreground => $namapalette{GroupForeground},
		-background => $namapalette{GroupBackground},
);
	$group_rw = $track_frame->Menubutton( 
		-text    => $group->rw,
	 	-tearoff => 0,
		-foreground => $namapalette{GroupForeground},
		-background => $namapalette{GroupBackground},
);


		
		$group_rw->AddItems([
			'command' => 'REC',
			-background => $old_bg,
			-command => sub { 
				return if eval_iam("engine-status") eq 'running';
				$group->set(rw => 'REC');
				$group_rw->configure(-text => 'REC');
				refresh();
				generate_setup() and connect_transport()
				}
			],[
			'command' => 'MON',
			-background => $old_bg,
			-command => sub { 
				return if eval_iam("engine-status") eq 'running';
				$group->set(rw => 'MON');
				$group_rw->configure(-text => 'MON');
				refresh();
				generate_setup() and connect_transport()
				}
			],[
			'command' => 'OFF',
			-background => $old_bg,
			-command => sub { 
				return if eval_iam("engine-status") eq 'running';
				$group->set(rw => 'OFF');
				$group_rw->configure(-text => 'OFF');
				refresh();
				generate_setup() and connect_transport()
				}
			]);
			$dummy->grid($group_label, $group_version, $group_rw);
			$ui->global_version_buttons;

}
sub global_version_buttons {
	local $debug = 0;
	my $version = $group_version;
	$version and map { $_->destroy } $version->children;
		
	$debug and print "making global version buttons range:",
		join ' ',1..$ti[-1]->group_last, " \n";

			$version->radiobutton( 

				-label => (''),
				-value => 0,
				-command => sub { 
					$tracker->set(version => 0); 
					$version->configure(-text => " ");
					generate_setup() and connect_transport();
					refresh();
					}
			);

 	for my $v (1..$ti[-1]->group_last) { 

	# the highest version number of all tracks in the
	# $tracker group
	
	my @user_track_indices = grep { $_ > 2 } map {$_->n} Audio::Ecasound::Multitrack::Track::all;
	
		next unless grep{  grep{ $v == $_ } @{ $ti[$_]->versions } }
			@user_track_indices;
		

			$version->radiobutton( 

				-label => ($v ? $v : ''),
				-value => $v,
				-command => sub { 
					$tracker->set(version => $v); 
					$version->configure(-text => $v);
					generate_setup() and connect_transport();
					refresh();
					}

			);
 	}
}
sub track_gui { 
	$debug2 and print "&track_gui\n";
	@_ = discard_object(@_);
	my $n = shift;
	
	$debug and print "found index: $n\n";
	my @rw_items = @_ ? @_ : (
			[ 'command' => "REC",
				-foreground => 'red',
				-command  => sub { 
					return if eval_iam("engine-status") eq 'running';
					$ti[$n]->set(rw => "REC");
					
					refresh_track($n);
					refresh_group();
			}],
			[ 'command' => "MON",
				-command  => sub { 
					return if eval_iam("engine-status") eq 'running';
					$ti[$n]->set(rw => "MON");
					refresh_track($n);
					refresh_group();
			}],
			[ 'command' => "OFF", 
				-command  => sub { 
					return if eval_iam("engine-status") eq 'running';
					$ti[$n]->set(rw => "OFF");
					refresh_track($n);
					refresh_group();
			}],
		);
	my ($number, $name, $version, $rw, $ch_r, $ch_m, $vol, $mute, $solo, $unity, $pan, $center);
	$number = $track_frame->Label(-text => $n,
									-justify => 'left');
	my $stub = " ";
	$stub .= $ti[$n]->active;
	$name = $track_frame->Label(
			-text => $ti[$n]->name,
			-justify => 'left');
	$version = $track_frame->Menubutton( 
					-text => $stub,
					-tearoff => 0);
	my @versions = '';
	#push @versions, @{$ti[$n]->versions} if @{$ti[$n]->versions};
	my $ref = ref $ti[$n]->versions ;
		$ref =~ /ARRAY/ and 
		push (@versions, @{$ti[$n]->versions}) or
		croak "chain $n, found unexpectedly $ref\n";;
	my $indicator;
	for my $v (@versions) {
					$version->radiobutton(
						-label => $v,
						-value => $v,
						-variable => \$indicator,
						-command => 
		sub { 
			$ti[$n]->set( active => $v );
			return if $ti[$n]->rec_status eq "REC";
			$version->configure( -text=> $ti[$n]->current_version ) 
			}
					);
	}

	$ch_r = $track_frame->Menubutton(
					-tearoff => 0,
				);
	my @range;
	push @range, "";
	push @range, 1..$tk_input_channels if $n > 2;
	
	for my $v (@range) {
		$ch_r->radiobutton(
			-label => $v,
			-value => $v,
			-command => sub { 
				return if eval_iam("engine-status") eq 'running';
			#	$ti[$n]->set(rw => 'REC');
				$ti[$n]->set(ch_r  => $v);
				refresh_track($n) }
			)
	}
	$ch_m = $track_frame->Menubutton(
					-tearoff => 0,
				);
				for my $v ("off",3..10) {
					$ch_m->radiobutton(
						-label => $v,
						-value => $v,
						-command => sub { 
							return if eval_iam("engine-status") eq 'running';
			#				$ti[$n]->set(rw  => "MON");
							$ti[$n]->send($v);
							refresh_track($n) }
				 		)
				}
	$rw = $track_frame->Menubutton(
		-text => $ti[$n]->rw,
		-tearoff => 0,
	);
	map{$rw->AddItems($_)} @rw_items; 

 
	# Volume

	my $p_num = 0; # needed when using parameter controllers
	my $vol_id = $ti[$n]->vol;

	local $debug = 0;


	$debug and print "vol cop_id: $vol_id\n";
	my %p = ( 	parent => \$track_frame,
			chain  => $n,
			type => 'ea',
			cop_id => $vol_id,
			p_num		=> $p_num,
			length => 300, 
			);


	 $debug and do {my %q = %p; delete $q{parent}; print
	 "=============\n%p\n",yaml_out(\%q)};

	$vol = make_scale ( \%p );
	# Mute

	$mute = $track_frame->Button(
	  		-command => sub { 
				if ($copp{$vol_id}->[0]) {  # non-zero volume
					$old_vol{$n}=$copp{$vol_id}->[0];
					$copp{$vol_id}->[0] = 0;
					effect_update($p{chain}, $p{cop_id}, $p{p_num}, 0);
					$mute->configure(-background => $namapalette{Mute});
					$mute->configure(-activebackground => $namapalette{Mute});
				}
				else {
					$copp{$vol_id}->[0] = $old_vol{$n};
					effect_update($p{chain}, $p{cop_id}, $p{p_num}, 
						$old_vol{$n});
					$old_vol{$n} = 0;
					$mute->configure(-background => $old_bg);
					$mute->configure(-activebackground => $old_abg);
				}
			}	
	  );


	# Unity

	$unity = $track_frame->Button(
	  		-command => sub { 
				$copp{$vol_id}->[0] = 100;
	 			effect_update($p{chain}, $p{cop_id}, $p{p_num}, 100);
			}
	  );

	  
	# Pan
	
	my $pan_id = $ti[$n]->pan;
	
	$debug and print "pan cop_id: $pan_id\n";
	$p_num = 0;           # first parameter
	my %q = ( 	parent => \$track_frame,
			chain  => $n,
			type => 'epp',
			cop_id => $pan_id,
			p_num		=> $p_num,
			);
	# $debug and do { my %q = %p; delete $q{parent}; print "x=============\n%p\n",yaml_out(\%q) };
	$pan = make_scale ( \%q );

	# Center

	$center = $track_frame->Button(
	  	-command => sub { 
			$copp{$pan_id}->[0] = 50;
			effect_update($q{chain}, $q{cop_id}, $q{p_num}, 50);
		}
	  );
	
	my $effects = $effect_frame->Frame->pack(-fill => 'both');;

	# effects, held by track_widget->n->effects is the frame for
	# all effects of the track

	@{ $track_widget{$n} }{qw(name version rw ch_r ch_m mute effects)} 
		= ($name,  $version, $rw, $ch_r, $ch_m, $mute, \$effects);#a ref to the object
	#$debug and print "=============\n\%track_widget\n",yaml_out(\%track_widget);
	my $independent_effects_frame 
		= ${ $track_widget{$n}->{effects} }->Frame->pack(-fill => 'x');


	my $controllers_frame 
		= ${ $track_widget{$n}->{effects} }->Frame->pack(-fill => 'x');
	
	# parents are the independent effects
	# children are controllers for various paramters

	$track_widget{$n}->{parents} = $independent_effects_frame;

	$track_widget{$n}->{children} = $controllers_frame;
	
	$independent_effects_frame
		->Label(-text => uc $ti[$n]->name )->pack(-side => 'left');

	#$debug and print( "Number: $n\n"),MainLoop if $n == 2;
	my @tags = qw( EF P1 P2 L1 L2 L3 L4 );
	my @starts =   ( $e_bound{cop}{a}, 
					 $e_bound{preset}{a}, 
					 $e_bound{preset}{b}, 
					 $e_bound{ladspa}{a}, 
					 $e_bound{ladspa}{b}, 
					 $e_bound{ladspa}{c}, 
					 $e_bound{ladspa}{d}, 
					);
	my @ends   =   ( $e_bound{cop}{z}, 
					 $e_bound{preset}{b}, 
					 $e_bound{preset}{z}, 
					 $e_bound{ladspa}{b}-1, 
					 $e_bound{ladspa}{c}-1, 
					 $e_bound{ladspa}{d}-1, 
					 $e_bound{ladspa}{z}, 
					);
	my @add_effect;

	map{push @add_effect, effect_button($n, shift @tags, shift @starts, shift @ends)} 1..@tags;
	
	$number->grid($name, $version, $rw, $ch_r, $ch_m, $vol, $mute, $unity, $pan, $center, @add_effect);
	refresh_track($n);

}
sub create_master_and_mix_tracks { 
	$debug2 and print "&create_master_and_mix_tracks\n";


	my @rw_items = (
			[ 'command' => "MON",
				-command  => sub { 
						return if eval_iam("engine-status") eq 'running';
						$tn{Master}->set(rw => "MON");
						refresh_track($master_track->n);
			}],
			[ 'command' => "OFF", 
				-command  => sub { 
						return if eval_iam("engine-status") eq 'running';
						$tn{Master}->set(rw => "OFF");
						refresh_track($master_track->n);
			}],
		);

	track_gui( $master_track->n, @rw_items );

	track_gui( $mixdown_track->n); 

	group_gui('Tracker');
}


sub update_version_button {
	@_ = discard_object(@_);
	my ($n, $v) = @_;
	carp ("no version provided \n") if ! $v;
	my $w = $track_widget{$n}->{version};
					$w->radiobutton(
						-label => $v,
						-value => $v,
						-command => 
		sub { $track_widget{$n}->{version}->configure(-text=>$v) 
				unless $ti[$n]->rec_status eq "REC" }
					);
}

sub add_effect_gui {
		$debug2 and print "&add_effect_gui\n";
		@_ = discard_object(@_);
		my %p 			= %{shift()};
		my $n 			= $p{chain};
		my $code 			= $p{type};
		my $parent_id = $p{parent_id};  
		my $id		= $p{cop_id};   # initiates restore
		my $parameter		= $p{parameter}; 
		my $i = $effect_i{$code};

		$debug and print yaml_out(\%p);

		$debug and print "cop_id: $id, parent_id: $parent_id\n";
		# $id is determined by cop_add, which will return the
		# existing cop_id if supplied

		# check display format, may be 'scale' 'field' or 'hidden'
		
		my $display_type = $cops{$id}->{display}; # individual setting
		defined $display_type or $display_type = $effects[$i]->{display}; # template
		$debug and print "display type: $display_type\n";

		return if $display_type eq q(hidden);

		my $frame ;
		if ( ! $parent_id ){ # independent effect
			$frame = $track_widget{$n}->{parents}->Frame->pack(
				-side => 'left', 
				-anchor => 'nw',)
		} else {                 # controller
			$frame = $track_widget{$n}->{children}->Frame->pack(
				-side => 'top', 
				-anchor => 'nw')
		}

		$effects_widget{$id} = $frame; 
		# we need a separate frame so title can be long

		# here add menu items for Add Controller, and Remove

		my $parentage = $effects[ $effect_i{ $cops{$parent_id}->{type}} ]
			->{name};
		$parentage and $parentage .=  " - ";
		$debug and print "parentage: $parentage\n";
		my $eff = $frame->Menubutton(
			-text => $parentage. $effects[$i]->{name}, -tearoff => 0,);

		$eff->AddItems([
			'command' => "Remove",
			-command => sub { remove_effect($id) }
		]);
		$eff->grid();
		my @labels;
		my @sliders;

		# make widgets

		for my $p (0..$effects[$i]->{count} - 1 ) {
		my @items;
		#$debug and print "p_first: $p_first, p_last: $p_last\n";
		for my $j ($e_bound{ctrl}{a}..$e_bound{ctrl}{z}) {   
			push @items, 				
				[ 'command' => $effects[$j]->{name},
					-command => sub { add_effect ({
							parent_id => $id,
							chain => $n,
							parameter  => $p,
							type => $effects[$j]->{code} } )  }
				];

		}
		push @labels, $frame->Menubutton(
				-text => $effects[$i]->{params}->[$p]->{name},
				-menuitems => [@items],
				-tearoff => 0,
		);
			$debug and print "parameter name: ",
				$effects[$i]->{params}->[$p]->{name},"\n";
			my $v =  # for argument vector 
			{	parent => \$frame,
				cop_id => $id, 
				p_num  => $p,
			};
			push @sliders,make_scale($v);
		}

		if (@sliders) {

			$sliders[0]->grid(@sliders[1..$#sliders]);
			 $labels[0]->grid(@labels[1..$#labels]);
		}
}


sub project_label_configure{ 
	@_ = discard_object(@_);
	$project_label->configure( @_ ) }

sub length_display{ 
	@_ = discard_object(@_);
	$setup_length->configure(@_)};

sub clock_config { 
	@_ = discard_object(@_);
	$clock->configure( @_ )}

sub manifest { $ew->deiconify() }

sub destroy_widgets {

	map{ $_->destroy } map{ $_->children } $effect_frame;
	#my @children = $group_frame->children;
	#map{ $_->destroy  } @children[1..$#children];
	my @children = $track_frame->children;
	# leave field labels (first row)
	map{ $_->destroy  } @children[11..$#children]; # fragile
	%mark_widget and map{ $_->destroy } values %mark_widget;
}

sub effect_button {
	local $debug = 0;	
	$debug2 and print "&effect_button\n";
	my ($n, $label, $start, $end) = @_;
	$debug and print "chain $n label $label start $start end $end\n";
	my @items;
	my $widget;
	my @indices = ($start..$end);
	if ($start >= $e_bound{ladspa}{a} and $start <= $e_bound{ladspa}{z}){
		@indices = ();
		@indices = @ladspa_sorted[$start..$end];
		$debug and print "length sorted indices list: ".scalar @indices. "\n";
	$debug and print "Indices: @indices\n";
	}
		
		for my $j (@indices) { 
		push @items, 				
			[ 'command' => "$effects[$j]->{count} $effects[$j]->{name}" ,
				-command  => sub { 
					 add_effect( {chain => $n, type => $effects[$j]->{code} } ); 
					$ew->deiconify; # display effects window
					} 
			];
	}
	$widget = $track_frame->Menubutton(
		-text => $label,
		-tearoff =>0,
		-menuitems => [@items],
	);
	$widget;
}

sub make_scale {
	
	$debug2 and print "&make_scale\n";
	my $ref = shift;
	my %p = %{$ref};
# 	%p contains following:
# 	cop_id   => operator id, to access dynamic effect params in %copp
# 	parent => parent widget, i.e. the frame
# 	p_num      => parameter number, starting at 0
# 	length       => length widget # optional 
	my $id = $p{cop_id};
	my $n = $cops{$id}->{chain};
	my $code = $cops{$id}->{type};
	my $p  = $p{p_num};
	my $i  = $effect_i{$code};

	$debug and print "id: $id code: $code\n";
	

	# check display format, may be text-field or hidden,

	$debug and  print "i: $i code: $effects[$i]->{code} display: $effects[$i]->{display}\n";
	my $display_type = $cops{$id}->{display};
	defined $display_type or $display_type = $effects[$i]->{display};
	$debug and print "display type: $display_type\n";
	return if $display_type eq q(hidden);


	$debug and print "to: ", $effects[$i]->{params}->[$p]->{end}, "\n";
	$debug and print "p: $p code: $code\n";

	# set display type to individually specified value if it exists
	# otherwise to the default for the controller class


	
	if 	($display_type eq q(scale) ) { 

		# return scale type controller widgets
		my $frame = ${ $p{parent} }->Frame;
			

		#return ${ $p{parent} }->Scale(
		
		my $log_display;
		
		my $controller = $frame->Scale(
			-variable => \$copp{$id}->[$p],
			-orient => 'horizontal',
			-from   =>   $effects[$i]->{params}->[$p]->{begin},
			-to   =>     $effects[$i]->{params}->[$p]->{end},
			-resolution => ($effects[$i]->{params}->[$p]->{resolution} 
				?  $effects[$i]->{params}->[$p]->{resolution}
				: abs($effects[$i]->{params}->[$p]->{end} - 
					$effects[$i]->{params}->[$p]->{begin} ) > 30 
						? 1 
						: abs($effects[$i]->{params}->[$p]->{end} - 
							$effects[$i]->{params}->[$p]->{begin} ) / 100),
		  -width => 12,
		  -length => $p{length} ? $p{length} : 100,
		  -command => sub { effect_update($n, $id, $p, $copp{$id}->[$p]) }
		  );

		# auxiliary field for logarithmic display
		if ($effects[$i]->{params}->[$p]->{hint} =~ /logarithm/ )
		#	or $code eq 'ea') 
		
			{
			my $log_display = $frame->Label(
				-text => exp $effects[$i]->{params}->[$p]->{default},
				-width => 5,
				);
			$controller->configure(
		  		-command => sub { 
					effect_update($n, $id, $p, exp $copp{$id}->[$p]);
					$log_display->configure(
						-text => 
						$effects[$i]->{params}->[$p]->{name} =~ /hz/i
							? int exp $copp{$id}->[$p]
							: dn(exp $copp{$id}->[$p], 1)
						);
					}
				);
		$log_display->grid($controller);
		}
		else { $controller->grid; }

		return $frame;

	}	

	elsif ($display_type eq q(field) ){ 

	 	# then return field type controller widget

		return ${ $p{parent} }->Entry(
			-textvariable =>\$copp{$id}->[$p],
			-width => 6,
	#		-command => sub { effect_update($n, $id, $p, $copp{$id}->[$p]) },
			# doesn't work with Entry widget
			);	

	}
	else { croak "missing or unexpected display type: $display_type" }

}
sub arm_mark_toggle { 
	if ($markers_armed) {
		$markers_armed = 0;
		$mark_remove->configure( -background => $old_bg);
	}
	else{
		$markers_armed = 1;
		$mark_remove->configure( -background => $namapalette{MarkArmed});
	}
}
sub marker {
	@_ = discard_object( @_); # UI
	my $mark = shift; # Mark
	#print "mark is ", ref $mark, $/;
	my $pos = $mark->time;
	#print $pos, " ", int $pos, $/;
		$mark_widget{$pos} = $mark_frame->Button( 
			-text => (join " ",  colonize( int $pos ), $mark->name),
			-background => $old_bg,
			-command => sub { mark($mark) },
		)->pack(-side => 'left');
}

sub restore_time_marks {
	@_ = discard_object( @_);
# 	map {$_->dumpp} Audio::Ecasound::Multitrack::Mark::all(); 
#	Audio::Ecasound::Multitrack::Mark::all() and 
	map{ $ui->marker($_) } Audio::Ecasound::Multitrack::Mark::all() ; 
	$time_step->configure( -text => $unit == 1 ? q(Sec) : q(Min) )
}
sub destroy_marker {
	@_ = discard_object( @_);
	my $pos = shift;
	$mark_widget{$pos}->destroy; 
}

sub wraparound {
	@_ = Audio::Ecasound::Multitrack::discard_object @_;
	my ($diff, $start) = @_;
	cancel_wraparound();
	$event_id{tk_wraparound} = $set_event->after( 
		int( $diff*1000 ), sub{ Audio::Ecasound::Multitrack::set_position( $start) } )
}
sub cancel_wraparound { tk_event_cancel("tk_wraparound") }

sub start_heartbeat {
	#print ref $set_event; 
	$event_id{tk_heartbeat} = $set_event->repeat( 
		3000, \&Audio::Ecasound::Multitrack::heartbeat);
		# 3000, *Audio::Ecasound::Multitrack::heartbeat{SUB}); # equivalent to above
}
sub poll_jack {
	package Audio::Ecasound::Multitrack;
	$event_id{tk_poll_jack} = $set_event->repeat( 
		5000, sub{ $jack_running = jack_running()}
	);
}
sub stop_heartbeat { tk_event_cancel( qw(tk_heartbeat tk_wraparound)) }

sub tk_event_cancel {
	@_ = Audio::Ecasound::Multitrack::discard_object @_;
	map{ (ref $event_id{$_}) =~ /Tk/ and $set_event->afterCancel($event_id{$_}) 
	} @_;
}
sub get_saved_colors {

	# aliases
	
	*old_bg = \$palette{mw}{background};
	*old_abg = \$palette{mw}{activeBackground};


	my $pal = join_path($project_root, $palette_file);
	if (-f $pal){
		print "$pal: found palette file, assigning palettes\n";
		assign_var( $pal,
			qw[%palette %namapalette]
		);
	*rec = \$namapalette{RecBackground};
	*mon = \$namapalette{MonBackground};
	*off = \$namapalette{OffBackground};
	} else {
		print "$pal: no palette file found, using default init\n";
		init_palette();
		init_namapalette();
	}
	$old_bg = $palette{mw}{background};
	$old_bg = $project_label->cget('-background') unless $old_bg;
	$old_abg = $palette{mw}{activeBackground};
	$old_abg = $project_label->cget('-activebackground') unless $old_abg;
	#print "1palette: \n", yaml_out( \%palette );
	#print "\n1namapalette: \n", yaml_out(\%namapalette);
	my %setformat;
	map{ $setformat{$_} = $palette{mw}{$_} if $palette{mw}{$_}  } 
		keys %{$palette{mw}};	
	#print "\nsetformat: \n", yaml_out(\%setformat);
	$mw->setPalette( %setformat );
}
sub init_palette {
	
# 	@palettefields, # set by setPalette method
# 	@namafields,    # field names for color palette used by nama
# 	%namapalette,     # nama's indicator colors
# 	%palette,  # overall color scheme

	my @parents = qw[
		mw
		ew
	];

# 		transport
# 		mark
# 		jump
# 		clock
# 		group
# 		track
# 		add

	map{ 	my $p = $_; # parent key
			map{	$palette{$p}->{$_} = $parent{$p}->cget("-$_")
						if $parent{$p}->cget("-$_") ;
				} @palettefields;
		} @parents;

}
sub init_namapalette {
		
	%namapalette = ( 
			'RecForeground' => 'Black',
			'RecBackground' => 'LightPink',
			'MonForeground' => 'Black',
			'MonBackground' => 'AntiqueWhite',
			'OffForeground' => 'Black',
			'OffBackground' => $old_bg,
	) unless %namapalette; # i.e. not if already loaded

	*rec = \$namapalette{RecBackground};
	*mon = \$namapalette{MonBackground};
	*off = \$namapalette{OffBackground};

	%namapalette = ( %namapalette, 
			'ClockForeground' 	=> 'Red',
			'ClockBackground' 	=> $old_bg,
			'Capture' 			=> $rec,
			'Play' 				=> 'LightGreen',
			'Mixdown' 			=> 'Yellow',
			'GroupForeground' 	=> 'Red',
			'GroupBackground' 	=> 'AntiqueWhite',
			'SendForeground' 	=> 'Black',
			'SendBackground' 	=> $mon,
			'SourceForeground' 	=> 'Black',
			'SourceBackground' 	=> $rec,
			'Mute'				=> 'Brown',
			'MarkArmed'			=> 'Yellow',
	) unless $namapalette{Play}; # i.e. not if already loaded

}
sub Audio::Ecasound::Multitrack::colorset {
	my ($field,$initial) = @_;
	sub { my $new_color = colorchooser($field,$initial);
			if( defined $new_color ){
				
				# install color in palette listing
				$palette{mw}{$field} = $new_color;

				# set the color
				my @fields =  ($field => $new_color);
				push (@fields, 'background', $mw->cget('-background'))
					unless $field eq 'background';
				#print "fields: @fields\n";
				$mw->setPalette( @fields );
			}
 	};
}

sub Audio::Ecasound::Multitrack::namaset {
	my ($field,$initial) = @_;
	sub { 	my $color = colorchooser($field,$initial);
			if ($color){ 
				# install color in palette listing
				$namapalette{$field} = $color;

				# set those objects who are not
				# handled by refresh

				$clock->configure(
					-background => $namapalette{ClockBackground},
					-foreground => $namapalette{ClockForeground},
				);
				$group_label->configure(
					-background => $namapalette{GroupBackground},
					-foreground => $namapalette{GroupForeground},
				)
			}
	}

}

sub Audio::Ecasound::Multitrack::colorchooser { 
	#print "colorchooser\n";
	#my $debug = 1;
	my ($field, $initialcolor) = @_;
	$debug and print "field: $field, initial color: $initialcolor\n";
	my $new_color = $mw->chooseColor(
							-title => $field,
							-initialcolor => $initialcolor,
							);
	#print "new color: $new_color\n";
	$new_color;
}
sub init_palettefields {
	@palettefields = qw[ 
		foreground
		background
		activeForeground
		activeBackground
		selectForeground
		selectBackground
		selectColor
		highlightColor
		highlightBackground
		disabledForeground
		insertBackground
		troughColor
	];

	@namafields = qw [
		RecForeground
		RecBackground
		MonForeground
		MonBackground
		OffForeground
		OffBackground
		ClockForeground
		ClockBackground
		Capture
		Play
		Mixdown
		GroupForeground
		GroupBackground
		SendForeground
		SendBackground
		SourceForeground
		SourceBackground
		Mute
		MarkArmed
	];
}

sub save_palette {
	package Audio::Ecasound::Multitrack;
 	serialize (
 		-file => join_path($project_root, $palette_file),
 		-vars => [ qw( %palette %namapalette ) ],
 		-class => 'Audio::Ecasound::Multitrack')
}


### end


## refresh functions

sub set_widget_color {
	my ($widget, $status) = @_;
	my %rw_foreground = (	REC  => $namapalette{RecForeground},
						 	MON => $namapalette{MonForeground},
						 	OFF => $namapalette{OffForeground},
						);

	my %rw_background =  (	REC  => $rec,
							MON  => $mon,
							OFF  => $off );
		
#	print "namapalette:\n",yaml_out( \%namapalette);
#	print "rec: $rec, mon: $mon, off: $off\n";

	$widget->configure( -background => $rw_background{$status} );
	$widget->configure( -foreground => $rw_foreground{$status} );
}


	
sub refresh_group { # tracker group 
	$debug2 and print "&refresh_group\n";
	
	
		my $status;
		if ( 	grep{ $_->rec_status eq 'REC'} 
				map{ $tn{$_} }
				$tracker->tracks ){

			$status = 'REC'

		}elsif(	grep{ $_->rec_status eq 'MON'} 
				map{ $tn{$_} }
				$tracker->tracks ){

			$status = 'MON'

		}else{ 
		
			$status = 'OFF' }

$debug and print "group status: $status\n";

	set_widget_color($group_rw, $status); 



	croak "some crazy status |$status|\n" if $status !~ m/rec|mon|off/i;
		#$debug and print "attempting to set $status color: ", $take_color{$status},"\n";

	set_widget_color( $group_rw, $status) if $group_rw;
}
sub refresh_track {
	
	#my $debug = 1;
	@_ = discard_object(@_);
	my $n = shift;
	$debug2 and print "&refresh_track\n";
	
	my $rec_status = $ti[$n]->rec_status;
	$debug and print "track: $n rec_status: $rec_status\n";

	#return unless $track_widget{$n}; # hidden track
	
	# set the text for displayed fields

	$track_widget{$n}->{rw}->configure(-text => $rec_status);
	$track_widget{$n}->{ch_r}->configure( -text => 
				$n > 2
					? $ti[$n]->source
					:  q() );
	$track_widget{$n}->{ch_m}->configure( -text => $ti[$n]->send);
	$track_widget{$n}->{version}->configure(-text => $ti[$n]->current_version);
	
	map{ set_widget_color( 	$track_widget{$n}->{$_}, 
							$rec_status)
	} qw(name rw );
	
	set_widget_color( 	$track_widget{$n}->{ch_r},
							$rec_status eq 'REC'
								? 'MON'
								: 'OFF');
	
	set_widget_color( $track_widget{$n}->{ch_m},
							$rec_status eq 'OFF' 
								? 'OFF'
								: $ti[$n]->send 
									? 'MON'
									: 'OFF');
}

sub refresh {  
	remove_small_wavs();
 	$ui->refresh_group(); 
	map{ $ui->refresh_track($_) } map{$_->n} Audio::Ecasound::Multitrack::Track::all();
}
sub refresh_oids{ # OUTPUT buttons
	map{ $widget_o{$_}->configure( # uses hash
			-background => 
				$oid_status{$_} ?  'AntiqueWhite' : $old_bg,
			-activebackground => 
				$oid_status{$_} ? 'AntiqueWhite' : $old_bg
			) } keys %widget_o;
}

### end


## The following code loads the object core of the system 
## and initiates the chain templates (rules)

use Audio::Ecasound::Multitrack::Track;   

package Audio::Ecasound::Multitrack::Graphical;  ## gui routines
our @ISA = 'Audio::Ecasound::Multitrack';      ## default to root class

## The following methods belong to the Graphical interface class

sub hello {"make a window";}
sub new { my $class = shift; return bless {@_}, $class }
sub loop {
    package Audio::Ecasound::Multitrack;
    #MainLoop;
    $term = new Term::ReadLine("Ecasound/Nama");
	my $attribs = $term->Attribs;
	$attribs->{attempted_completion_function} = \&complete;
	$term->tkRunning(1);
	$ui->poll_jack();
    $OUT = $term->OUT || \*STDOUT;
	while (1) {
    my ($user_input) = $term->readline($prompt) ;
	next if $user_input =~ /^\s*$/;
     $term->addhistory($user_input) ;
	command_process( $user_input );
	}
}

## The following methods belong to the Text interface class

package Audio::Ecasound::Multitrack::Text;
our @ISA = 'Audio::Ecasound::Multitrack';
use Carp;
sub hello {"hello world!";}

## no-op graphic methods 

# those that take parameters will break!!!
# because object and procedural access get
# different parameter lists ($self being included);

sub init_gui {}
sub transport_gui {}
sub group_gui {}
sub track_gui {}
sub preview_button {}
sub create_master_and_mix_tracks {}
sub time_gui {}
sub refresh {}
sub refresh_group {}
sub refresh_track {}
sub flash_ready {}
sub update_master_version_button {}
sub update_version_button {}
sub paint_button {}
sub refresh_oids {}
sub project_label_configure{}
sub length_display{}
sub clock_display {}
sub clock_config {}
sub manifest {}
sub global_version_buttons {}
sub destroy_widgets {}
sub destroy_marker {}
sub restore_time_marks {}
sub show_unit {};
sub add_effect_gui {};
sub remove_effect_gui {};
sub marker {};
sub initialize_palette {};
sub save_palette {};
## Some of these, may be overwritten
## by definitions that follow

use Carp;
use Text::Format;
use Audio::Ecasound::Multitrack::Assign qw(:all);
$text = new Text::Format {
	columns 		=> 65,
	firstIndent 	=> 0,
	bodyIndent		=> 0,
	tabstop			=> 4,
};

sub new { my $class = shift; return bless { @_ }, $class; }

sub show_versions {
 	print "All versions: ", join " ", @{$this_track->versions}, $/;
}

sub show_effects {
 	map { 
 		my $op_id = $_;
 		 my $i = $effect_i{ $cops{ $op_id }->{type} };
 		 print $op_id, ": " , $effects[ $i ]->{name},  " ";
 		 my @pnames =@{$effects[ $i ]->{params}};
			map{ print join " ", 
			 	$pnames[$_]->{name}, 
				$copp{$op_id}->[$_],'' 
		 	} (0..scalar @pnames - 1);
		 print $/;
 
 	 } @{ $this_track->ops };
}
sub show_modifiers {
	print "Modifiers: ",$this_track->modifiers, $/;
}

sub poll_jack {
	package Audio::Ecasound::Multitrack;
	$event_id{Event_poll_jack} = Event->timer(
	    desc   => 'poll_jack',               # description;
	    prio   => 5,                         # low priority;
		interval => 5,
	    cb     => sub{ $jack_running = jack_running() },  # callback;
	);
}

sub loop {

	# first setup Term::Readline::GNU

	# we are using Event's handlers and event loop
	package Audio::Ecasound::Multitrack;
	Audio::Ecasound::Multitrack::Text::poll_jack();
	$term = new Term::ReadLine("Ecasound/Nama");
	my $attribs = $term->Attribs;
	$attribs->{attempted_completion_function} = \&complete;
	$term->callback_handler_install($prompt, \&process_line);

	# store output buffer in a scalar (for print)
	my $outstream=$attribs->{'outstream'};

	# install STDIN handler
	$event_id{stdin} = Event->io(
		desc   => 'STDIN handler',           # description;
		fd     => \*STDIN,                   # handle;
		poll   => 'r',	                   # watch for incoming chars
		cb     => sub{ &{$attribs->{'callback_read_char'}}() }, # callback;
		repeat => 1,                         # keep alive after event;
	 );

	$event_id{Event_heartbeat} = Event->timer(
		parked => 1, 						# start it later
	    desc   => 'heartbeat',               # description;
	    prio   => 5,                         # low priority;
		interval => 3,
	    cb     => \&heartbeat,               # callback;
	);
	if ( $midi_inputs =~ /on|capture/ ){
		my $command = "aseqdump ";
		$command .= "-p $controller_ports" if $controller_ports;
		open MIDI, "$command |" or die "can't fork $command: $!";
		$event_id{sequencer} = Event->io(
			desc   => 'read ALSA sequencer events',
			fd     => \*MIDI,                    # handle;
			poll   => 'r',	                     # watch for incoming chars
			cb     => \&process_control_inputs, # callback;
			repeat => 1,                         # keep alive after event;
		 );
		$event_id{sequencer_error} = Event->io(
			desc   => 'read ALSA sequencer events',
			fd     => \*MIDI,                    # handle;
			poll   => 'e',	                     # watch for exception
			cb     => sub { die "sequencer pipe read failed" }, # callback;
		 );
	
	}
	Event::loop();

}
sub wraparound {
	package Audio::Ecasound::Multitrack;
	@_ = discard_object(@_);
	my ($diff, $start) = @_;
	#print "diff: $diff, start: $start\n";
	$event_id{Event_wraparound}->cancel()
		if defined $event_id{Event_wraparound};
	$event_id{Event_wraparound} = Event->timer(
	desc   => 'wraparound',               # description;
	after  => $diff,
	cb     => sub{ set_position($start) }, # callback;
   );

}


sub start_heartbeat {$event_id{Event_heartbeat}->start() }

sub stop_heartbeat {$event_id{Event_heartbeat}->stop() }

sub cancel_wraparound {
	$event_id{Event_wraparound}->cancel() if defined $event_id{Event_wraparound}
}


sub placeholder { $use_placeholders ? q(--) : q() }
sub show_tracks {
    no warnings;
    my @tracks = @_;
    map {     push @format_fields,  
            $_->n,
            $_->name,
            $_->current_version || placeholder(),
            $_->rw,
            $_->rec_status,
            $_->name =~ /Master|Mixdown/ ? placeholder() : 
				$_->rec_status eq 'REC' ? $_->source : placeholder(),
			$_->name =~ /Master|Mixdown/ ? placeholder() : 
				$_->rec_status ne 'OFF' 
					? ($_->send ? $_->send : placeholder())
					: placeholder(),
            #(join " ", @{$_->versions}),

        } grep{ ! $_-> hide} @tracks;
        
    write; # using format below
    $- = 0; # $FORMAT_LINES_LEFT # force header on next output
    1;
    use warnings;
    no warnings q(uninitialized);
}

format STDOUT_TOP =
Track  Name        Ver. Setting  Status   Source      Send
=============================================================
.
format STDOUT =
@>>    @<<<<<<<<<  @|||   @<<     @<<    @|||||||  @|||||||||  ~~
splice @format_fields, 0, 7
.

sub helpline {
	my $cmd = shift;
	my $text = "Command: $cmd\n";
	$text .=  "Shortcuts: $commands{$cmd}->{short}\n"
			if $commands{$cmd}->{short};	
	$text .=  $commands{$cmd}->{what}. $/;
	$text .=  "parameters: ". $commands{$cmd}->{parameters} . $/
			if $commands{$cmd}->{parameters};	
	$text .=  "example: ". eval( qq("$commands{$cmd}->{example}") ) . $/  
			if $commands{$cmd}->{example};
	($/, ucfirst $text, $/);
	
}
sub helptopic {
	my $index = shift;
	$index =~ /^(\d+)$/ and $index = $help_topic[$index];
	my @output;
	push @output, "\n-- ", ucfirst $index, " --\n\n";
	push @output, $help_topic{$index}, $/;
	@output;
}

sub help { 
	my $name = shift;
	chomp $name;
	#print "seeking help for argument: $name\n";
	$iam_cmd{$name} and print <<IAM;

$name is an Ecasound command.  See 'man ecasound-iam'.
IAM
	my @output;
	if ( $help_topic{$name}){
		@output = helptopic($name);
	} elsif ($name == 10){
		@output = map{ helptopic $_ } @help_topic;
	} elsif ( $name =~ /^(\d+)$/ and $1 < 20  ){
		@output = helptopic($name)
	} elsif ( $commands{$name} ){
		@output = helpline($name)
	} else {
		my %helped = (); 
		my @help = ();
		map{  
			my $cmd = $_ ;
			if ($cmd =~ /$name/){
				push( @help, helpline($cmd));
				$helped{$cmd}++ ;
			}
			if ( ! $helped{$cmd} and
					grep{ /$name/ } split " ", $commands{$cmd}->{short} ){
				push @help, helpline($cmd) 
			}
		} keys %commands;
		if ( @help ){ push @output, 
			qq("$name" matches the following commands:\n\n), @help;
		}
	}
	Audio::Ecasound::Multitrack::pager( @output ); 
	
}
sub help_effect {
	my $input = shift;
	print "input: $input\n";
	# e.g. help tap_reverb    
	#      help 2142
	#      help var_chipmunk # preset


	if ($input !~ /\D/){ # all digits
		$input = $ladspa_label{$input}
			or print("$input: effect not found.\n\n"), return;
	}
	if ( $effect_i{$input} ) {} # do nothing
	elsif ( $effect_j{$input} ) { $input = $effect_j{$input} }
	else { print("$input: effect not found.\n\n"), return }
	if ($input =~ /pn:/) {
		print grep{ /$input/  } @effects_help;
	}
	elsif ( $input =~ /el:/) {
	
	my @output = $ladspa_help{$input};
	print "label: $input\n";
	Audio::Ecasound::Multitrack::pager( @output );
	#print $ladspa_help{$input};
	} else { 
	print "$input: Ecasound effect. Type 'man ecasound' for details.\n";
	}
}


sub find_effect {
	my @keys = @_;
	#print "keys: @keys\n";
	#my @output;
	my @matches = grep{ 
		my $help = $_; 
		my $didnt_match;
		map{ $help =~ /\Q$_\E/i or $didnt_match++ }  @keys;
		! $didnt_match; # select if no cases of non-matching
	} @effects_help;
	if ( @matches ){
# 		push @output, <<EFFECT;
# 
# Effects matching "@keys" were found. The "pn:" prefix 
# indicates an Ecasound preset. The "el:" prefix indicates
# a LADSPA plugin. No prefix indicates an Ecasound chain
# operator.
# 
# EFFECT
	Audio::Ecasound::Multitrack::pager( $text->paragraphs(@matches) , "\n" );
	} else { print "No matching effects.\n\n" }
}


sub t_load_project {
	package Audio::Ecasound::Multitrack;
	my $name = shift;
	print "input name: $name\n";
	my $newname = remove_spaces($name);
	$newname =~ s(/$)(); # remove trailing slash
	print ("Project $newname does not exist\n"), return
		unless -d join_path project_root(), $newname; 
	load_project( name => $newname );
	print "loaded project: $project_name\n";
}

    
sub t_create_project {
	package Audio::Ecasound::Multitrack;
	my $name = shift;
	load_project( 
		name => remove_spaces($name),
		create => 1,
	);
	print "created project: $project_name\n";

}
sub t_add_ctrl {
	package Audio::Ecasound::Multitrack;
	my ($parent, $code, $values) = @_;
	print "code: $code, parent: $parent\n";
	$values and print "values: ", join " ", @{$values};
	if ( $effect_i{$code} ) {} # do nothing
	elsif ( $effect_j{$code} ) { $code = $effect_j{$code} }
	else { warn "effect code not found: $code\n"; return }
	print "code: ", $code, $/;
		my %p = (
				chain => $cops{$parent}->{chain},
				parent_id => $parent,
				values => $values,
				type => $code,
			);
			print "adding effect\n";
			# print (yaml_out(\%p));
		add_effect( \%p );
}
sub t_insert_effect {
	my ($before, $code, $values) = @_;
	print ("Cannot (yet) insert effect while engine running\n"), return 
		if Audio::Ecasound::Multitrack::engine_running;
	# and Audio::Ecasound::Multitrack::really_recording;
	my $n = $cops{ $before }->{chain} or 
		print(qq[Insertion point "$before" does not exist.  Skipping.\n]), 
		return;
	# should mute if engine running
	my $track = $ti[$n];
	print $track->name, $/;
	print join " ",@{$track->ops}, $/; 
	t_add_effect( $code, $values );
	print join " ",@{$track->ops}, $/; 
	my $op = pop @{$track->ops};
	print join " ",@{$track->ops}, $/; 
	my $offset = 0;
	for my $id ( @{$track->ops} ){
		last if $id eq $before;
		$offset++;
	}
	# now reposition the effect
	splice 	@{$track->ops}, $offset, 0, $op;
	print join " ",@{$track->ops}, $/; 
}
sub t_add_effect {
	package Audio::Ecasound::Multitrack;
	my ($code, $values)  = @_;

	# allow use of LADSPA unique ID
	
    if ($code !~ /\D/){ # i.e. $code is all digits
		$code = $ladspa_label{$code} 
			or carp("$code: LADSPA plugin not found.  Aborting.\n"), return;
	}
	if ( $effect_i{$code} ) {} # do nothing
	elsif ( $effect_j{$code} ) { $code = $effect_j{$code} }
	else { warn "effect code not found: $code\n"; return }
	print "code: ", $code, $/;
		my %p = (
			chain => $this_track->n,
			values => $values,
			type => $code,
			);
			print "adding effect\n";
			#print (yaml_out(\%p));
		add_effect( \%p );
}
sub group_rec { 
	print "Setting group REC-enable. You may record user tracks.\n";
	$tracker->set( rw => 'REC'); }
sub group_mon { 
	print "Setting group MON mode. No recording on user tracks.\n";
	$tracker->set( rw => 'MON');}
sub group_off {
	print "Setting group OFF mode. All user tracks disabled.\n";
	$tracker->set(rw => 'OFF'); } 

sub mixdown {
	print "Enabling mixdown to file.\n";
	$mixdown_track->set(rw => 'REC'); }
sub mixplay { 
	print "Setting mixdown_track playback mode.\n";
	$mixdown_track->set(rw => 'MON');
	$tracker->set(rw => 'OFF');}
sub mixoff { 
	print "Leaving mixdown_track mode.\n";
	$mixdown_track->set(rw => 'OFF');
	$tracker->set(rw => 'MON')}

sub bunch {
	package Audio::Ecasound::Multitrack;
	my ($bunchname, @tracks) = @_;
	if (! $bunchname){
		Audio::Ecasound::Multitrack::pager(yaml_out( \%bunch ));
	} elsif (! @tracks){
		$bunch{$bunchname} 
			and print "bunch $bunchname: @{$bunch{$bunchname}}\n" 
			or  print "bunch $bunchname: does not exist.\n";
	} elsif (my @mispelled = grep { ! $tn{$_} and ! $ti[$_]} @tracks){
		print "@mispelled: mispelled track(s), skipping.\n";
	} else {
	$bunch{$bunchname} = [ @tracks ];
	}
}


package Audio::Ecasound::Multitrack;

### COMMAND LINE PARSER 

$debug2 and print "Reading grammar\n";

$commands_yml = <<'YML';
---
help:
  what: display help 
  short: h
  parameters: topic or command name 
  type: general
exit:
  short: quit q
  what: exit program, saving settings
  type: general
stop:
  type: transport
  short: s
  what: stop transport
start:
  type: transport
  short: t
  what: start transport
loop_enable:
  type: transport
  short: loop
  what: playback will loop between two points
  parameters: start end (mark names/indices, or decimal seconds 1.5 125.0)
loop_disable:
  type: transport
  short: noloop nl
  what: disable automatic looping
loop_show:
  type: transport
  short: ls
  what: show loop status and endpoints (TODO)
getpos:
  type: transport
  short: gp
  what: get current playhead position (seconds)
  parameters: none
setpos:
  short: sp
  what: set current playhead position (seconds)
  example: setpos 65 (set play position to 65 seconds from start)
  parameters: float (position)
  type: transport
forward:
  short: fw
  what: move transport position forward
  parameters: seconds
  type: transport
rewind:
  short: rw
  what: move transport position backward
  parameters: seconds
  type: transport
beg:
  what: set playback head to start
  type: transport
  sub: to_start
end:
  what: set playback head to end minus 10 seconds 
  type: transport
  sub: to_end
ecasound_start:
  type: transport
  short: T
  what: ecasound-only start
ecasound_stop:
  type: transport
  short: S
  what: ecasound-only stop
preview:
  type: transport
  what: start engine with rec_file disabled (for mic test, etc.)
  parameters: none
doodle:
  type: transport
  what: disable mon_setup and rec_file, set unique_inputs_only
mixdown:
  type: mix
  short: mxd
  what: enable mixdown on subsequent engine runs
  smry: enable mixdown
  parameters: none
mixplay:
  type: mix
  short: mxp
  what: Play back mixdown file, with user tracks OFF
  smry: Playback mix
  parameters: none
mixoff:
  type: mix
  short: mxo
  what: Mixdown group OFF, user tracks MON
  smry: mix off
  parameters: none
add_track:
  type: track
  short: add new
  what: create one or more new tracks
  example: add sax violin tuba
  parameters: name1 name2 name3...
set_track:
  short: set
  type: track
  what: directly set values in current track (use with care!)
  smry: set object fields
  example: set ch_m 5   (direct monitor output for current track to channel 5)
rec:
  type: track
  what: rec enable 
  parameters: none
mon:
  type: track
  what: set track to MON
  parameters: none
off:
  type: track
  short: z
  what: set track OFF (exclude from chain setup)
  smry: set track OFF 
  parameters: none
monitor_channel:
  type: track
  short: m
  what: set track output channel number
  smry: set track output channel
  parameters: number
source:
  type: track
  what: set track source
  short: src r
  parameters: JACK client name or soundcard channel number 
send:
  type: track
  what: set auxilary track destination
  short: out aux m
  parameters: JACK client name or soundcard channel number 3 or higher. (Soundcard channels 1 and 2 are reserved for the mixer.)
jack:
  type: general
  short: jackon jon
  what: Set mixer output to JACK device, tracks may use JACK signal inputs
nojack:
  short: nj jackoff joff
  type: general
  what: disable JACK functions
stereo:
  type: track
  what: record two channels for current track
mono:
  type: track
  what: record one channel for current track
set_version:
  type: track
  short: version n ver
  what: set track version number for monitoring (overrides group version setting)
  smry: select track version
  parameters: number
  example: sax; version 5; sh
destroy_current_wav:
  type: track
  what: unlink $track->full_path
group_rec:
  type: group
  short: grec R
  what: rec-enable user tracks
  parameters: none
group_mon:
  type: group
  short: gmon M
  what: rec-disable user tracks
  parameters: none
group_version:
  type: group 
  short: gn gver gv
  what: set group version for monitoring (overridden by track-version settings)
  smry: get/set group version
group_off:
  type: group
  short: goff Z 
  what: group OFF mode, exclude all user tracks from chain setup
  smry: group OFF mode
  parameters: none
bunch:
  type: group
  short: bn
  what: define a group of tracks | list one bunch | list bunch names
  parameters: group_name track1 track2 track3...
list_versions:
  type: track
  short: lver lv
  what: list version numbers of current track
  smry: list track versions
  parameters: none
vol:
  type: track
  short: v
  what: get/set track volume, current track
  smry: get/set track volume
  parameters: number
mute:
  type: track
  short: c cut
  what: set playback volume to zero, current track
  smry: mute volume
  parameters: none
unmute:
  type: track
  short: cc uncut
  what: restore volume level before mute
unity:
  type: track
  what: set unity, i.e. 100 volume, current track
  smry: unity volume
  parameters: none
solo:
  type: track
  what: mute all but current track
  parameters: none
all:
  type: track
  what: restore all muted tracks
  parameters: none
  short: nosolo
pan:
  type: track
  short: p	
  what: get/set pan position, current track
  smry: get/set pan position
  parameters: number
pan_right:
  type: track
  short: pr
  what: pan track fully right
  parameters: none
pan_left:
  type: track
  short: pl
  what: pan track fully left
  parameters: none
pan_center:
  type: track
  short: pc
  what: set pan center
  parameters: none
pan_back:
  type: track
  short: pb
  what: restore pan setting prior to pl, pr, or pc commands
  smry: restore pan
  parameters: none
save_state:
  type: project
  short: keep k save
  what: save project settings to disk, optional name
  parameters: optional string
get_state:
  type: project
  short: recall restore retrieve
  what: retrieve project settings
list_projects:
  type: project
  short: listp
  what: list project directory
create_project:
  type: project
  short: create	
  what: create a new project directory tree
  example: create pauls_gig
  parameters: string
load_project:
  type: project
  short: load	
  what: load an existing project, or recall from last save
  smry: load project settings
  parameters: project_name
  example: load pauls_gig
generate:
  type: setup
  short: gen
  what: generate chain setup for audio processing
  parameters: none
arm:
  type: setup
  short: generate_and_connect
  what: generate and connect chain setup
  parameters: none
connect:
  type: setup
  short: con
  what: connect chain setup
  parameters: none
disconnect:
  type: setup
  short: dcon
  what: disconnect chain setup
  parameters: none
engine_status:
  type: setup
  what: ecasound audio processing engine status
  smry: engine status info
  short: egs
show_chain_setup:
  type: setup
  short: chains setup
  what: show current Ecasound chain setup
  smry: show chain setup
show_io:
  type: setup
  short: showio
  what: show chain input and output fragments
  smry: show chain fragments
show_tracks:
  type: setup
  short: show tracks
  what: show track status
show_track:
  type: track
  short: sh
  what: show track status, effects, versions
modifiers:
  type: track
  short: mods mod 
  what: set/show track modifiers 
  example: modifiers select 5 15.2 reverse playat 78.2 audioloop
nomodifiers:
  type: track
  short: nomods nomod
  what: remove modifiers from current track
show_effects:
  type: effect
  what: show effects on current track
  short: fxs sfx
  parameters: none
add_ctrl:
  type: effect
  what: add a controller to an operator
  parameters: parent_id effect_code param1 param2... paramn
  short: acl
add_effect:
  type: effect
  what: add effect to current track
  short: fxa afx
  smry: add effect
  parameters: effect_label param1 param2,... paramn
  example: fxa amp 6 (LADSPA Simple amp 6dB gain); fxa var_dali (preset var_dali) Note: no el: or pn: prefix is required
insert_effect:
  type: effect
  short: ifx fxi
  what: place effect before specified effect (engine stopped, prior to arm only)
  parameters: before_id effect_code param1 param2... paramn
modify_effect:
  type: effect
  what: modify an effect parameter
  parameters: effect_id, parameter, optional_sign, value
  short: fxm mfx
  example: fxm V 1 1000 (set to 1000), fxm V 1 -10 (reduce by 10) 
remove_effect:
  type: effect
  what: remove effects from selected track
  short: fxr rfx
  parameters: effect_id1, effect_id2,...
  example: fxr V (remove effect V)
help_effect:
  type: help
  short: hfx fxh hf he
  parameters: label | unique_id
  what: display analyseplugin output or one-line preset help
find_effect:
  type: help
  short: ffx fxf ff fe
  what: display one-line help for effects matching search strings
  parameters: string1, string2,...
ctrl_register:
  type: effect
  what: list Ecasound controllers
  short: crg
preset_register:
  type: effect
  what: list Ecasound presets 
  short: prg
ladspa_register:
  type: effect
  what: list LADSPA plugins
  short: lrg
list_marks:
  type: mark
  short: lm
  what: List all marks
  parameters: none
to_mark:
  type: mark
  short: tom
  what: move playhead to named mark or mark index
  smry: playhead to mark
  parameters: string or integer
  example: tom start (go to mark named 'start')
mark:
  type: mark
  short: k
  what: Mark current head position 
  parameter: name (optional)
  smry: mark current position
  short: k	
  parameters: none
remove_mark:
  type: mark
  what: Remove mark 
  short: rmm
  parameters: mark name, mark index or none (for current mark) 
  example: rmm start (remove mark named 'start')
next_mark:
  type: mark
  short: nm
  what: Move playback head to next mark
  parameters: none
previous_mark:
  type: mark
  short: pm
  what: Move playback head to previous mark
  parameters: none
name_mark:
  type: mark
  short: nmk nom
  what: Give a name to the current mark
  parameters: string
  example: nmk start
remove_track:
  type: mark
  what: Make track go away (non destructive)
  parameters: string
  example: remove_track sax
project_name:
  type: project
  what: show current project name
  short: project pn
dump_track:
  type: diagnostics
  what: dump current track data to screen (YAML format)
  short: dump
  smry: dump track data
dump_group:
  type: diagnostics 
  what: dump the settings of the group for user tracks 
  short: dumpg
  smry: dump group settings
dump_all:
  type: diagnostics
  what: dump all internal state
  short: dumpall dumpa
midi_inputs:
  type: perform
  what: use MIDI messages to control parameters
  short: midi
  parameters: on/off/capture  
erase_capture:
  type: perform
  short: erase
  what: erase recorded controller inputs
  parameters: optional range, as decimal times in seconds, or mark names or indices 
perform:
  type: perform
  what: playback recorded controller inputs
  short: perform perf
  parameters: on/off
bind_midi:
  type: perform
  parameters: midi_port midi_controller chain_op_id parameter multiplier offset (log)
  what: bind a midi controller to a chain operator parameter
  short: bind
bind_off:
  type: perform
  what: remove MIDI binding
  parameters: midi_port midi_controller
normalize:
  type: track
  short: norm ecanormalize
  what: apply ecanormalize to current track version
fixdc:
  type: track
  what: apply ecafixdc to current track version
  short: ecafixdc
memoize:
  type: general
  what: enable WAV dir cache
unmemoize:
  type: general
  what: disable WAV dir cache
...

YML

$cop_hints_yml = <<'YML';
---
-
  code: ea
  count: 1
  display: scale
  name: Volume
  params:
    -
      begin: 0
      default: 100
      end: 600
      name: "Level %"
      resolution: 0
-
  code: epp
  count: 1
  display: scale
  name: Pan
  params:
    -
      begin: 0
      default: 50
      end: 100
      name: "Level %"
      resolution: 0
-
  code: eal
  count: 1
  display: scale
  name: Limiter
  params:
    -
      begin: 0
      default: 100
      end: 100
      name: "Limit %"
      resolution: 0
-
  code: ec
  count: 2
  display: scale
  name: Compressor
  params:
    -
      begin: 0
      default: 1
      end: 1
      name: "Compression Rate (Db)"
      resolution: 0
    -
      begin: 0
      default: 50
      end: 100
      name: "Threshold %"
      resolution: 0
-
  code: eca
  count: 4
  display: scale
  name: "Advanced Compressor"
  params:
    -
      begin: 0
      default: 69
      end: 100
      name: "Peak Level %"
      resolution: 0
    -
      begin: 0
      default: 2
      end: 5
      name: "Release Time (Seconds)"
      resolution: 0
    -
      begin: 0
      default: 0.5
      end: 1
      name: "Fast Compressor Rate"
      resolution: 0
    -
      begin: 0
      default: 1
      end: 1
      name: "Compressor Rate (Db)"
      resolution: 0
-
  code: enm
  count: 5
  display: scale
  name: "Noise Gate"
  params:
    -
      begin: 0
      default: 100
      end: 100
      name: "Threshold Level %"
      resolution: 0
    -
      begin: 0
      default: 200
      end: 2000
      name: "Pre Hold Time (ms)"
      resolution: 0
    -
      begin: 0
      default: 200
      end: 2000
      name: "Attack Time (ms)"
      resolution: 0
    -
      begin: 0
      default: 200
      end: 2000
      name: "Post Hold Time (ms)"
      resolution: 0
    -
      begin: 0
      default: 200
      end: 2000
      name: "Release Time (ms)"
      resolution: 0
-
  code: ef1
  count: 2
  display: scale
  name: "Resonant Bandpass Filter"
  params:
    -
      begin: 0
      default: 0
      end: 20000
      name: "Center Frequency (Hz)"
      resolution: 0
    -
      begin: 0
      default: 0
      end: 2000
      name: "Width (Hz)"
      resolution: 0
-
  code: ef3
  count: 3
  display: scale
  name: "Resonant Lowpass Filter"
  params:
    -
      begin: 0
      default: 0
      end: 5000
      name: "Cutoff Frequency (Hz)"
      resolution: 0
    -
      begin: 0
      default: 0
      end: 2
      name: Resonance
      resolution: 0
    -
      begin: 0
      default: 0
      end: 1
      name: Gain
      resolution: 0
-
  code: efa
  count: 2
  display: scale
  name: "Allpass Filter"
  params:
    -
      begin: 0
      default: 0
      end: 10000
      name: "Delay Samples"
      resolution: 0
    -
      begin: 0
      default: 50
      end: 100
      name: "Feedback %"
      resolution: 0
-
  code: efb
  count: 2
  display: scale
  name: "Bandpass Filter"
  params:
    -
      begin: 0
      default: 11000
      end: 11000
      name: "Center Frequency (Hz)"
      resolution: 0
    -
      begin: 0
      default: 22000
      end: 22000
      name: "Width (Hz)"
      resolution: 0
-
  code: efh
  count: 1
  display: scale
  name: "Highpass Filter"
  params:
    -
      begin: 10000
      default: 10000
      end: 22000
      name: "Cutoff Frequency (Hz)"
      resolution: 0
-
  code: efl
  count: 1
  display: scale
  name: "Lowpass Filter"
  params:
    -
      begin: 0
      default: 0
      end: 10000
      name: "Cutoff Frequency (Hz)"
      resolution: 0
-
  code: efr
  count: 2
  display: scale
  name: "Bandreject Filter"
  params:
    -
      begin: 0
      default: 11000
      end: 11000
      name: "Center Frequency (Hz)"
      resolution: 0
    -
      begin: 0
      default: 22000
      end: 22000
      name: "Width (Hz)"
      resolution: 0
-
  code: efs
  count: 2
  display: scale
  name: "Resonator Filter"
  params:
    -
      begin: 0
      default: 11000
      end: 11000
      name: "Center Frequency (Hz)"
      resolution: 0
    -
      begin: 0
      default: 22000
      end: 22000
      name: "Width (Hz)"
      resolution: 0
-
  code: etd
  count: 4
  display: scale
  name: Delay
  params:
    -
      begin: 0
      default: 200
      end: 2000
      name: "Delay Time (ms)"
      resolution: 0
    -
      begin: 0
      default: 0
      end: 2
      name: "Surround Mode (Normal, Surround St., Spread)"
      resolution: 1
    -
      begin: 0
      default: 50
      end: 100
      name: "Number of Delays"
      resolution: 0
    -
      begin: 0
      default: 50
      end: 100
      name: "Mix %"
      resolution: 0
-
  code: etc
  count: 4
  display: scale
  name: Chorus
  params:
    -
      begin: 0
      default: 200
      end: 2000
      name: "Delay Time (ms)"
      resolution: 0
    -
      begin: 0
      default: 500
      end: 10000
      name: "Variance Time Samples"
      resolution: 0
    -
      begin: 0
      default: 50
      end: 100
      name: "Feedback %"
      resolution: 0
    -
      begin: 0
      default: 50
      end: 100
      name: "LFO Frequency (Hz)"
      resolution: 0
-
  code: etr
  count: 3
  display: scale
  name: Reverb
  params:
    -
      begin: 0
      default: 200
      end: 2000
      name: "Delay Time (ms)"
      resolution: 0
    -
      begin: 0
      default: 0
      end: 1
      name: "Surround Mode (0=Normal, 1=Surround)"
      resolution: 1
    -
      begin: 0
      default: 50
      end: 100
      name: "Feedback %"
      resolution: 0
-
  code: ete
  count: 3
  display: scale
  name: "Advanced Reverb"
  params:
    -
      begin: 0
      default: 10
      end: 100
      name: "Room Size (Meters)"
      resolution: 0
    -
      begin: 0
      default: 50
      end: 100
      name: "Feedback %"
      resolution: 0
    -
      begin: 0
      default: 50
      end: 100
      name: "Wet %"
      resolution: 0
-
  code: etf
  count: 1
  display: scale
  name: "Fake Stereo"
  params:
    -
      begin: 0
      default: 40
      end: 500
      name: "Delay Time (ms)"
      resolution: 0
-
  code: etl
  count: 4
  display: scale
  name: Flanger
  params:
    -
      begin: 0
      default: 200
      end: 1000
      name: "Delay Time (ms)"
      resolution: 0
    -
      begin: 0
      default: 200
      end: 10000
      name: "Variance Time Samples"
      resolution: 0
    -
      begin: 0
      default: 50
      end: 100
      name: "Feedback %"
      resolution: 0
    -
      begin: 0
      default: 50
      end: 100
      name: "LFO Frequency (Hz)"
      resolution: 0
-
  code: etm
  count: 3
  display: scale
  name: "Multitap Delay"
  params:
    -
      begin: 0
      default: 200
      end: 2000
      name: "Delay Time (ms)"
      resolution: 0
    -
      begin: 0
      default: 20
      end: 100
      name: "Number of Delays"
      resolution: 0
    -
      begin: 0
      default: 50
      end: 100
      name: "Mix %"
      resolution: 0
-
  code: etp
  count: 4
  display: scale
  name: Phaser
  params:
    -
      begin: 0
      default: 200
      end: 2000
      name: "Delay Time (ms)"
      resolution: 0
    -
      begin: 0
      default: 100
      end: 10000
      name: "Variance Time Samples"
      resolution: 0
    -
      begin: 0
      default: 50
      end: 100
      name: "Feedback %"
      resolution: 0
    -
      begin: 0
      default: 50
      end: 100
      name: "LFO Frequency (Hz)"
      resolution: 0
-
  code: pn:metronome
  count: 1
  display: scale
  name: Metronome
  params:
    -
      begin: 30
      default: 120
      end: 300
      name: BPM
      resolution: 1
...
;
YML

%commands = %{ Audio::Ecasound::Multitrack::yaml_in( $Audio::Ecasound::Multitrack::commands_yml) };

$Audio::Ecasound::Multitrack::AUTOSTUB = 1;
$Audio::Ecasound::Multitrack::RD_TRACE = 1;
$Audio::Ecasound::Multitrack::RD_ERRORS = 1; # Make sure the parser dies when it encounters an error
$Audio::Ecasound::Multitrack::RD_WARN   = 1; # Enable warnings. This will warn on unused rules &c.
$Audio::Ecasound::Multitrack::RD_HINT   = 1; # Give out hints to help fix problems.
# rec command changes active take

$grammar = q(


key: /\w+/
someval: /[\w.+-]+/
sign: /[\/*-+]/
op_id: /[A-Z]+/
parameter: /\d+/
value: /[\d\.eE+-]+/
last: ('last' | '$' ) 
dd: /\d+/
name: /[\w:]+\/?/
name2: /[\w-]+/
name3: /\S+/
modifier: 'audioloop' | 'select' | 'reverse' | 'playat' | value
nomodifiers: _nomodifiers end { $Audio::Ecasound::Multitrack::this_track->set(modifiers => ""); 1}
end: /[;\s]*$/ 
help_effect: _help_effect name end { Audio::Ecasound::Multitrack::Text::help_effect($item{name}) ; 1}
find_effect: _find_effect name3(s) { 
	Audio::Ecasound::Multitrack::Text::find_effect(@{$item{"name3(s)"}}); 1}
help: _help 'yml' end { Audio::Ecasound::Multitrack::pager($Audio::Ecasound::Multitrack::commands_yml); 1}
help: _help name2  { Audio::Ecasound::Multitrack::Text::help($item{name2}) ; 1}
help: _help end { print $Audio::Ecasound::Multitrack::help_screen ; 1}
project_name: _project_name end { 
	print "project name: ", $Audio::Ecasound::Multitrack::project_name, $/; 1}
create_project: _create_project name end { 
	Audio::Ecasound::Multitrack::Text::t_create_project $item{name} ; 1}
list_projects: _list_projects end { Audio::Ecasound::Multitrack::list_projects() ; 1}
load_project: _load_project name end {
	Audio::Ecasound::Multitrack::Text::t_load_project $item{name} ; 1}
save_state: _save_state name end { Audio::Ecasound::Multitrack::save_state( $item{name}); 1}
save_state: _save_state end { Audio::Ecasound::Multitrack::save_state(); 1}
get_state: _get_state name end {
 	Audio::Ecasound::Multitrack::load_project( 
 		name => $Audio::Ecasound::Multitrack::project_name,
 		settings => $item{name}
 		); 1}
get_state: _get_state end {
 	Audio::Ecasound::Multitrack::load_project( name => $Audio::Ecasound::Multitrack::project_name,) ; 1}
getpos: _getpos end {  
	print Audio::Ecasound::Multitrack::d1( Audio::Ecasound::Multitrack::eval_iam q(getpos) ), $/; 1}
setpos: _setpos value end {
	Audio::Ecasound::Multitrack::set_position($item{value}); 1}
forward: _forward value end {
	Audio::Ecasound::Multitrack::forward( $item{value} ); 1}
rewind: _rewind value end {
	Audio::Ecasound::Multitrack::rewind( $item{value} ); 1}
add_track: _add_track name(s) end {
	Audio::Ecasound::Multitrack::add_track(@{$item{'name(s)'}}); 1}
set_track: _set_track key someval end {
	 $Audio::Ecasound::Multitrack::this_track->set( $item{key}, $item{someval} ); 1}
dump_track: _dump_track end { Audio::Ecasound::Multitrack::pager($Audio::Ecasound::Multitrack::this_track->dump); 1}
dump_group: _dump_group end { Audio::Ecasound::Multitrack::pager($Audio::Ecasound::Multitrack::tracker->dump); 1}
dump_all: _dump_all end { Audio::Ecasound::Multitrack::dump_all(); 1}
remove_track: _remove_track name end { $Audio::Ecasound::Multitrack::tn{ $item{name} }->set(hide => 1); 1}
generate: _generate end { Audio::Ecasound::Multitrack::generate_setup(); 1}
arm: _arm end { Audio::Ecasound::Multitrack::arm(); 1}
connect: _connect end { Audio::Ecasound::Multitrack::connect_transport(); 1}
disconnect: _disconnect end { Audio::Ecasound::Multitrack::disconnect_transport(); 1}
renew_engine: _renew_engine end { Audio::Ecasound::Multitrack::new_engine(); 1}
engine_status: _engine_status end { 
	print(Audio::Ecasound::Multitrack::eval_iam q(engine-status)); print "\n" ; 1}
start: _start end { Audio::Ecasound::Multitrack::start_transport(); 1}
stop: _stop end { Audio::Ecasound::Multitrack::stop_transport(); 1}
ecasound_start: _ecasound_start end { Audio::Ecasound::Multitrack::eval_iam("stop"); 1}
ecasound_stop: _ecasound_stop  end { Audio::Ecasound::Multitrack::eval_iam("start"); 1}
show_tracks: _show_tracks end { 	
	Audio::Ecasound::Multitrack::Text::show_tracks ( Audio::Ecasound::Multitrack::Track::all );
	use warnings; 
	no warnings qw(uninitialized); 
	print $/, "Group control", " " x 8, 
	  $Audio::Ecasound::Multitrack::tracker->rw, " " x 24 , $Audio::Ecasound::Multitrack::tracker->version, $/, $/;
	1;
}
modifiers: _modifiers modifier(s) end {
 	$Audio::Ecasound::Multitrack::this_track->set(modifiers => (join q(,),
	@{$item{"modifier(s)"}}, q() ));
	1;}
modifiers: _modifiers end { print $Audio::Ecasound::Multitrack::this_track->modifiers, "\n"; 1}
show_chain_setup: _show_chain_setup { Audio::Ecasound::Multitrack::show_chain_setup(); 1}
show_io: _show_io { Audio::Ecasound::Multitrack::show_io(); 1}
show_track: _show_track end {
	Audio::Ecasound::Multitrack::Text::show_tracks($Audio::Ecasound::Multitrack::this_track);
	Audio::Ecasound::Multitrack::Text::show_effects();
	Audio::Ecasound::Multitrack::Text::show_versions();
	Audio::Ecasound::Multitrack::Text::show_modifiers();
	1;}
show_track: _show_track name end { 
 	Audio::Ecasound::Multitrack::Text::show_tracks( 
	$Audio::Ecasound::Multitrack::tn{$item{name}} ) if $Audio::Ecasound::Multitrack::tn{$item{name}};
	1;}
show_track: _show_track dd end {  
	Audio::Ecasound::Multitrack::Text::show_tracks( $Audio::Ecasound::Multitrack::ti[$item{dd}] ) if
	$Audio::Ecasound::Multitrack::ti[$item{dd}];
	1;}
group_rec: _group_rec end { Audio::Ecasound::Multitrack::Text::group_rec(); 1}
group_mon: _group_mon end  { Audio::Ecasound::Multitrack::Text::group_mon(); 1}
group_off: _group_off end { Audio::Ecasound::Multitrack::Text::group_off(); 1}
mixdown: _mixdown end { Audio::Ecasound::Multitrack::Text::mixdown(); 1}
mixplay: _mixplay end { Audio::Ecasound::Multitrack::Text::mixplay(); 1}
mixoff:  _mixoff  end { Audio::Ecasound::Multitrack::Text::mixoff(); 1}
exit: _exit end { Audio::Ecasound::Multitrack::save_state($Audio::Ecasound::Multitrack::state_store_file); CORE::exit(); 1}
source: _source name { $Audio::Ecasound::Multitrack::this_track->set_source( $item{name} ); 1 }
source: _source end { 
	my $source = $Audio::Ecasound::Multitrack::this_track->source;
	my $object = Audio::Ecasound::Multitrack::Track::input_object( $source );
	print $Audio::Ecasound::Multitrack::this_track->name, ": input from $object.\n";
	1;
}
send: _send name { $Audio::Ecasound::Multitrack::this_track->set_send($item{name}); 1}
send: _send end { $Audio::Ecasound::Multitrack::this_track->set_send(); 1}
stereo: _stereo { 
	$Audio::Ecasound::Multitrack::this_track->set(ch_count => 2); 
	print $Audio::Ecasound::Multitrack::this_track->name, ": setting to stereo\n";
	1;
}
mono: _mono { 
	$Audio::Ecasound::Multitrack::this_track->set(ch_count => 1); 
	print $Audio::Ecasound::Multitrack::this_track->name, ": setting to mono\n";
	1; }
off: 'off' end {$Audio::Ecasound::Multitrack::this_track->set_off(); 1}
rec: 'rec' end { $Audio::Ecasound::Multitrack::this_track->set_rec(); 1}
mon: 'mon' end {$Audio::Ecasound::Multitrack::this_track->set_mon(); 1}
set_version: _set_version dd end { $Audio::Ecasound::Multitrack::this_track->set_version($item{dd}); 1}
vol: _vol value end { 
	$Audio::Ecasound::Multitrack::copp{ $Audio::Ecasound::Multitrack::this_track->vol }->[0] = $item{value}; 
	Audio::Ecasound::Multitrack::sync_effect_param( $Audio::Ecasound::Multitrack::this_track->vol, 0);
	1;} 
vol: _vol '+' value end { 
	$Audio::Ecasound::Multitrack::copp{ $Audio::Ecasound::Multitrack::this_track->vol }->[0] += $item{value};
	Audio::Ecasound::Multitrack::sync_effect_param( $Audio::Ecasound::Multitrack::this_track->vol, 0);
	1;} 
vol: _vol '-' value  end { 
	$Audio::Ecasound::Multitrack::copp{ $Audio::Ecasound::Multitrack::this_track->vol }->[0] -= $item{value} ;
	Audio::Ecasound::Multitrack::sync_effect_param( $Audio::Ecasound::Multitrack::this_track->vol, 0);
	1;} 
vol: _vol '*' value  end { 
	$Audio::Ecasound::Multitrack::copp{ $Audio::Ecasound::Multitrack::this_track->vol }->[0] *= $item{value} ;
	Audio::Ecasound::Multitrack::sync_effect_param( $Audio::Ecasound::Multitrack::this_track->vol, 0);
	1;} 
vol: _vol end { print $Audio::Ecasound::Multitrack::copp{$Audio::Ecasound::Multitrack::this_track->vol}[0], "\n" ; 1}
mute: _mute end { Audio::Ecasound::Multitrack::mute(); 1}
unmute: _unmute end { Audio::Ecasound::Multitrack::unmute(); 1}
solo: _solo end { Audio::Ecasound::Multitrack::solo(); 1}
all: _all end { Audio::Ecasound::Multitrack::all() ; 1}
unity: _unity end { 
	$Audio::Ecasound::Multitrack::copp{ $Audio::Ecasound::Multitrack::this_track->vol }->[0] = 100;
	Audio::Ecasound::Multitrack::sync_effect_param( $Audio::Ecasound::Multitrack::this_track->vol, 0);
	1;}
pan: _pan dd end { $Audio::Ecasound::Multitrack::copp{ $Audio::Ecasound::Multitrack::this_track->pan }->[0] = $item{dd};
	my $current = $Audio::Ecasound::Multitrack::copp{ $Audio::Ecasound::Multitrack::this_track->pan }->[0];
	$Audio::Ecasound::Multitrack::this_track->set(old_pan_level => $current);
	Audio::Ecasound::Multitrack::sync_effect_param( $Audio::Ecasound::Multitrack::this_track->pan, 0);
	1;} 
pan: _pan '+' dd end { $Audio::Ecasound::Multitrack::copp{ $Audio::Ecasound::Multitrack::this_track->pan }->[0] += $item{dd} ;
	my $current = $Audio::Ecasound::Multitrack::copp{ $Audio::Ecasound::Multitrack::this_track->pan }->[0];
	$Audio::Ecasound::Multitrack::this_track->set(old_pan_level => $current);
	Audio::Ecasound::Multitrack::sync_effect_param( $Audio::Ecasound::Multitrack::this_track->pan, 0);
	1;} 
pan: _pan '-' dd end { $Audio::Ecasound::Multitrack::copp{ $Audio::Ecasound::Multitrack::this_track->pan }->[0] -= $item{dd} ;
	my $current = $Audio::Ecasound::Multitrack::copp{ $Audio::Ecasound::Multitrack::this_track->pan }->[0];
	$Audio::Ecasound::Multitrack::this_track->set(old_pan_level => $current);
	Audio::Ecasound::Multitrack::sync_effect_param( $Audio::Ecasound::Multitrack::this_track->pan, 0);
	1;} 
pan: _pan end { print $Audio::Ecasound::Multitrack::copp{$Audio::Ecasound::Multitrack::this_track->pan}[0], "\n"; 1}
pan_right: _pan_right end { 
	$Audio::Ecasound::Multitrack::copp{ $Audio::Ecasound::Multitrack::this_track->pan }->[0] = 100;
	Audio::Ecasound::Multitrack::sync_effect_param( $Audio::Ecasound::Multitrack::this_track->pan, 0);
	1;}
pan_left:  _pan_left end { 
	$Audio::Ecasound::Multitrack::copp{ $Audio::Ecasound::Multitrack::this_track->pan }->[0] = 0; 
	Audio::Ecasound::Multitrack::sync_effect_param( $Audio::Ecasound::Multitrack::this_track->pan, 0);
	1;}
pan_center: _pan_center end { 
	$Audio::Ecasound::Multitrack::copp{ $Audio::Ecasound::Multitrack::this_track->pan }->[0] = 50   ;
	Audio::Ecasound::Multitrack::sync_effect_param( $Audio::Ecasound::Multitrack::this_track->pan, 0);
	1;}
pan_back:  _pan_back end {
	$Audio::Ecasound::Multitrack::copp{ $Audio::Ecasound::Multitrack::this_track->pan }->[0] = $Audio::Ecasound::Multitrack::this_track->old_pan_level;
	1;}
remove_mark: _remove_mark dd end {
	my @marks = Audio::Ecasound::Multitrack::Mark::all();
	$marks[$item{dd}]->remove if defined $marks[$item{dd}];
	1;}
remove_mark: _remove_mark name end { 
	my $mark = $Audio::Ecasound::Multitrack::Mark::by_name{$item{name}};
	$mark->remove if defined $mark;
	1;}
remove_mark: _remove_mark end { 
	return unless (ref $Audio::Ecasound::Multitrack::this_mark) =~ /Mark/;
	$Audio::Ecasound::Multitrack::this_mark->remove;
	1;}
mark: _mark name end { Audio::Ecasound::Multitrack::drop_mark $item{name}; 1}
mark: _mark end {  Audio::Ecasound::Multitrack::drop_mark(); 1}
next_mark: _next_mark end { Audio::Ecasound::Multitrack::next_mark(); 1}
previous_mark: _previous_mark end { Audio::Ecasound::Multitrack::previous_mark(); 1}
loop_enable: _loop_enable someval(s) end {
	my @new_endpoints = @{ $item{"someval(s)"}}; 
	$Audio::Ecasound::Multitrack::loop_enable = 1;
	@Audio::Ecasound::Multitrack::loop_endpoints = (@new_endpoints, @Audio::Ecasound::Multitrack::loop_endpoints); 
	@Audio::Ecasound::Multitrack::loop_endpoints = @Audio::Ecasound::Multitrack::loop_endpoints[0,1];
	1;}
loop_disable: _loop_disable end { $Audio::Ecasound::Multitrack::loop_enable = 0; 1}
name_mark: _name_mark name end {$Audio::Ecasound::Multitrack::this_mark->set_name( $item{name}); 1}
list_marks: _list_marks end { 
	my $i = 0;
	map{ print( $_->time == $Audio::Ecasound::Multitrack::this_mark->time ? q(*) : q()
	,join " ", $i++, sprintf("%.1f", $_->time), $_->name, "\n")  } 
		  @Audio::Ecasound::Multitrack::Mark::all;
	my $start = my $end = "undefined";
	print "now at ", sprintf("%.1f", Audio::Ecasound::Multitrack::eval_iam "getpos"), "\n";
	1;}
to_mark: _to_mark dd end {
	my @marks = Audio::Ecasound::Multitrack::Mark::all();
	$marks[$item{dd}]->jump_here;
	1;}
to_mark: _to_mark name end { 
	my $mark = $Audio::Ecasound::Multitrack::Mark::by_name{$item{name}};
	$mark->jump_here if defined $mark;
	1;}
remove_effect: _remove_effect op_id(s) end {
	map{ print "removing effect id: $_\n"; Audio::Ecasound::Multitrack::remove_effect( $_ )
	} grep { $_ }  @{ $item{"op_id(s)"}} ;
	1;}
add_ctrl: _add_ctrl parent name value(s?) end {
	my $code = $item{name};
	my $parent = $item{parent};
	my $values = $item{"value(s?)"};
	Audio::Ecasound::Multitrack::Text::t_add_ctrl $parent, $code, $values;
	1;}
parent: op_id
add_effect: _add_effect name value(s?)  end { 
	my $code = $item{name};
	my $values = $item{"value(s?)"};
	Audio::Ecasound::Multitrack::Text::t_add_effect $code, $values;
	1;}
insert_effect: _insert_effect before name value(s?) end {
	my $before = $item{before};
	my $code = $item{name};
	my $values = $item{"value(s?)"};
	print join ", ", @{$values} if $values;
	Audio::Ecasound::Multitrack::Text::t_insert_effect  $before, $code, $values;
	1;}
before: op_id
modify_effect: _modify_effect op_id parameter sign(?) value end {
		$item{parameter}--; 
		my $new_value = $item{value}; 
		if ($item{"sign(?)"} and @{ $item{"sign(?)"} }) {
			$new_value = 
 			eval (join " ",
 				$Audio::Ecasound::Multitrack::copp{$item{op_id}}->[$item{parameter}], 
 				@{$item{"sign(?)"}},
 				$item{value});
		}
	Audio::Ecasound::Multitrack::effect_update_copp_set( 
		$Audio::Ecasound::Multitrack::cops{ $item{op_id} }->{chain}, 
		$item{op_id}, 
		$item{parameter}, 
		$new_value);
	1;}
group_version: _group_version end { 
	use warnings;
	no warnings qw(uninitialized);
	print $Audio::Ecasound::Multitrack::tracker->version, "\n" ; 1}
group_version: _group_version dd end { 
	my $n = $item{dd};
	$n = undef if $n == 0;
	$Audio::Ecasound::Multitrack::tracker->set( version => $n ); 1}
bunch: _bunch name(s?) { Audio::Ecasound::Multitrack::Text::bunch( @{$item{'name(s?)'}}); 1}
list_versions: _list_versions end { 
	print join " ", @{$Audio::Ecasound::Multitrack::this_track->versions}, "\n"; 1}
ladspa_register: _ladspa_register end { 
	Audio::Ecasound::Multitrack::pager( Audio::Ecasound::Multitrack::eval_iam("ladspa-register")); 1}
preset_register: _preset_register end { 
	Audio::Ecasound::Multitrack::pager( Audio::Ecasound::Multitrack::eval_iam("preset-register")); 1}
ctrl_register: _ctrl_register end { 
	Audio::Ecasound::Multitrack::pager( Audio::Ecasound::Multitrack::eval_iam("ctrl-register")); 1}
preview: _preview { Audio::Ecasound::Multitrack::preview(); 1}
doodle: _doodle { Audio::Ecasound::Multitrack::doodle(); 1 }
normalize: _normalize { $Audio::Ecasound::Multitrack::this_track->normalize; 1}
fixdc: _fixdc { $Audio::Ecasound::Multitrack::this_track->fixdc; 1}
destroy_current_wav: _destroy_current_wav { 
	my $wav = $Audio::Ecasound::Multitrack::this_track->full_path;
	print "delete WAV file $wav? [n] ";
	my $reply = <STDIN>;
	if ( $reply =~ /y/i ){
		print "Unlinking.\n";
		unlink $wav or warn "couldn't unlink $wav: $!\n";
		Audio::Ecasound::Multitrack::rememoize();
	}
	1;
}
memoize: _memoize { 
	package Audio::Ecasound::Multitrack::Wav;
	$Audio::Ecasound::Multitrack::memoize = 1;
	memoize('candidates'); 1
}
unmemoize: _unmemoize {
	package Audio::Ecasound::Multitrack::Wav;
	$Audio::Ecasound::Multitrack::memoize = 0;
	unmemoize('candidates'); 1
}


command: add_ctrl
command: add_effect
command: add_track
command: all
command: arm
command: beg
command: bind_midi
command: bind_off
command: bunch
command: connect
command: create_project
command: ctrl_register
command: destroy_current_wav
command: disconnect
command: doodle
command: dump_all
command: dump_group
command: dump_track
command: ecasound_start
command: ecasound_stop
command: end
command: engine_status
command: erase_capture
command: exit
command: find_effect
command: fixdc
command: forward
command: generate
command: get_state
command: getpos
command: group_mon
command: group_off
command: group_rec
command: group_version
command: help
command: help_effect
command: insert_effect
command: jack
command: ladspa_register
command: list_marks
command: list_projects
command: list_versions
command: load_project
command: loop_disable
command: loop_enable
command: loop_show
command: mark
command: memoize
command: midi_inputs
command: mixdown
command: mixoff
command: mixplay
command: modifiers
command: modify_effect
command: mon
command: monitor_channel
command: mono
command: mute
command: name_mark
command: next_mark
command: nojack
command: nomodifiers
command: normalize
command: off
command: pan
command: pan_back
command: pan_center
command: pan_left
command: pan_right
command: perform
command: preset_register
command: preview
command: previous_mark
command: project_name
command: rec
command: remove_effect
command: remove_mark
command: remove_track
command: rewind
command: save_state
command: send
command: set_track
command: set_version
command: setpos
command: show_chain_setup
command: show_effects
command: show_io
command: show_track
command: show_tracks
command: solo
command: source
command: start
command: stereo
command: stop
command: to_mark
command: unity
command: unmemoize
command: unmute
command: vol
_add_ctrl: /add_ctrl\b/ | /acl\b/
_add_effect: /add_effect\b/ | /fxa\b/ | /afx\b/
_add_track: /add_track\b/ | /add\b/ | /new\b/
_all: /all\b/ | /nosolo\b/
_arm: /arm\b/ | /generate_and_connect\b/
_beg: /beg\b/
_bind_midi: /bind_midi\b/ | /bind\b/
_bind_off: /bind_off\b/
_bunch: /bunch\b/ | /bn\b/
_connect: /connect\b/ | /con\b/
_create_project: /create_project\b/ | /create\b/
_ctrl_register: /ctrl_register\b/ | /crg\b/
_destroy_current_wav: /destroy_current_wav\b/
_disconnect: /disconnect\b/ | /dcon\b/
_doodle: /doodle\b/
_dump_all: /dump_all\b/ | /dumpall\b/ | /dumpa\b/
_dump_group: /dump_group\b/ | /dumpg\b/
_dump_track: /dump_track\b/ | /dump\b/
_ecasound_start: /ecasound_start\b/ | /T\b/
_ecasound_stop: /ecasound_stop\b/ | /S\b/
_end: /end\b/
_engine_status: /engine_status\b/ | /egs\b/
_erase_capture: /erase_capture\b/ | /erase\b/
_exit: /exit\b/ | /quit\b/ | /q\b/
_find_effect: /find_effect\b/ | /ffx\b/ | /fxf\b/ | /ff\b/ | /fe\b/
_fixdc: /fixdc\b/ | /ecafixdc\b/
_forward: /forward\b/ | /fw\b/
_generate: /generate\b/ | /gen\b/
_get_state: /get_state\b/ | /recall\b/ | /restore\b/ | /retrieve\b/
_getpos: /getpos\b/ | /gp\b/
_group_mon: /group_mon\b/ | /gmon\b/ | /M\b/
_group_off: /group_off\b/ | /goff\b/ | /Z\b/
_group_rec: /group_rec\b/ | /grec\b/ | /R\b/
_group_version: /group_version\b/ | /gn\b/ | /gver\b/ | /gv\b/
_help: /help\b/ | /h\b/
_help_effect: /help_effect\b/ | /hfx\b/ | /fxh\b/ | /hf\b/ | /he\b/
_insert_effect: /insert_effect\b/ | /ifx\b/ | /fxi\b/
_jack: /jack\b/ | /jackon\b/ | /jon\b/
_ladspa_register: /ladspa_register\b/ | /lrg\b/
_list_marks: /list_marks\b/ | /lm\b/
_list_projects: /list_projects\b/ | /listp\b/
_list_versions: /list_versions\b/ | /lver\b/ | /lv\b/
_load_project: /load_project\b/ | /load\b/
_loop_disable: /loop_disable\b/ | /noloop\b/ | /nl\b/
_loop_enable: /loop_enable\b/ | /loop\b/
_loop_show: /loop_show\b/ | /ls\b/
_mark: /mark\b/ | /k\b/
_memoize: /memoize\b/
_midi_inputs: /midi_inputs\b/ | /midi\b/
_mixdown: /mixdown\b/ | /mxd\b/
_mixoff: /mixoff\b/ | /mxo\b/
_mixplay: /mixplay\b/ | /mxp\b/
_modifiers: /modifiers\b/ | /mods\b/ | /mod\b/
_modify_effect: /modify_effect\b/ | /fxm\b/ | /mfx\b/
_mon: /mon\b/
_monitor_channel: /monitor_channel\b/ | /m\b/
_mono: /mono\b/
_mute: /mute\b/ | /c\b/ | /cut\b/
_name_mark: /name_mark\b/ | /nmk\b/ | /nom\b/
_next_mark: /next_mark\b/ | /nm\b/
_nojack: /nojack\b/ | /nj\b/ | /jackoff\b/ | /joff\b/
_nomodifiers: /nomodifiers\b/ | /nomods\b/ | /nomod\b/
_normalize: /normalize\b/ | /norm\b/ | /ecanormalize\b/
_off: /off\b/ | /z\b/
_pan: /pan\b/ | /p\b/
_pan_back: /pan_back\b/ | /pb\b/
_pan_center: /pan_center\b/ | /pc\b/
_pan_left: /pan_left\b/ | /pl\b/
_pan_right: /pan_right\b/ | /pr\b/
_perform: /perform\b/ | /perform\b/ | /perf\b/
_preset_register: /preset_register\b/ | /prg\b/
_preview: /preview\b/
_previous_mark: /previous_mark\b/ | /pm\b/
_project_name: /project_name\b/ | /project\b/ | /pn\b/
_rec: /rec\b/
_remove_effect: /remove_effect\b/ | /fxr\b/ | /rfx\b/
_remove_mark: /remove_mark\b/ | /rmm\b/
_remove_track: /remove_track\b/
_rewind: /rewind\b/ | /rw\b/
_save_state: /save_state\b/ | /keep\b/ | /k\b/ | /save\b/
_send: /send\b/ | /out\b/ | /aux\b/ | /m\b/
_set_track: /set_track\b/ | /set\b/
_set_version: /set_version\b/ | /version\b/ | /n\b/ | /ver\b/
_setpos: /setpos\b/ | /sp\b/
_show_chain_setup: /show_chain_setup\b/ | /chains\b/ | /setup\b/
_show_effects: /show_effects\b/ | /fxs\b/ | /sfx\b/
_show_io: /show_io\b/ | /showio\b/
_show_track: /show_track\b/ | /sh\b/
_show_tracks: /show_tracks\b/ | /show\b/ | /tracks\b/
_solo: /solo\b/
_source: /source\b/ | /src\b/ | /r\b/
_start: /start\b/ | /t\b/
_stereo: /stereo\b/
_stop: /stop\b/ | /s\b/
_to_mark: /to_mark\b/ | /tom\b/
_unity: /unity\b/
_unmemoize: /unmemoize\b/
_unmute: /unmute\b/ | /cc\b/ | /uncut\b/
_vol: /vol\b/ | /v\b/
add_ctrl: _add_ctrl end { 1 }
add_effect: _add_effect end { 1 }
add_track: _add_track end { 1 }
all: _all end { 1 }
arm: _arm end { 1 }
beg: _beg end { 1 }
bind_midi: _bind_midi end { 1 }
bind_off: _bind_off end { 1 }
bunch: _bunch end { 1 }
connect: _connect end { 1 }
create_project: _create_project end { 1 }
ctrl_register: _ctrl_register end { 1 }
destroy_current_wav: _destroy_current_wav end { 1 }
disconnect: _disconnect end { 1 }
doodle: _doodle end { 1 }
dump_all: _dump_all end { 1 }
dump_group: _dump_group end { 1 }
dump_track: _dump_track end { 1 }
ecasound_start: _ecasound_start end { 1 }
ecasound_stop: _ecasound_stop end { 1 }
end: _end end { 1 }
engine_status: _engine_status end { 1 }
erase_capture: _erase_capture end { 1 }
exit: _exit end { 1 }
find_effect: _find_effect end { 1 }
fixdc: _fixdc end { 1 }
forward: _forward end { 1 }
generate: _generate end { 1 }
get_state: _get_state end { 1 }
getpos: _getpos end { 1 }
group_mon: _group_mon end { 1 }
group_off: _group_off end { 1 }
group_rec: _group_rec end { 1 }
group_version: _group_version end { 1 }
help: _help end { 1 }
help_effect: _help_effect end { 1 }
insert_effect: _insert_effect end { 1 }
jack: _jack end { 1 }
ladspa_register: _ladspa_register end { 1 }
list_marks: _list_marks end { 1 }
list_projects: _list_projects end { 1 }
list_versions: _list_versions end { 1 }
load_project: _load_project end { 1 }
loop_disable: _loop_disable end { 1 }
loop_enable: _loop_enable end { 1 }
loop_show: _loop_show end { 1 }
mark: _mark end { 1 }
memoize: _memoize end { 1 }
midi_inputs: _midi_inputs end { 1 }
mixdown: _mixdown end { 1 }
mixoff: _mixoff end { 1 }
mixplay: _mixplay end { 1 }
modifiers: _modifiers end { 1 }
modify_effect: _modify_effect end { 1 }
mon: _mon end { 1 }
monitor_channel: _monitor_channel end { 1 }
mono: _mono end { 1 }
mute: _mute end { 1 }
name_mark: _name_mark end { 1 }
next_mark: _next_mark end { 1 }
nojack: _nojack end { 1 }
nomodifiers: _nomodifiers end { 1 }
normalize: _normalize end { 1 }
off: _off end { 1 }
pan: _pan end { 1 }
pan_back: _pan_back end { 1 }
pan_center: _pan_center end { 1 }
pan_left: _pan_left end { 1 }
pan_right: _pan_right end { 1 }
perform: _perform end { 1 }
preset_register: _preset_register end { 1 }
preview: _preview end { 1 }
previous_mark: _previous_mark end { 1 }
project_name: _project_name end { 1 }
rec: _rec end { 1 }
remove_effect: _remove_effect end { 1 }
remove_mark: _remove_mark end { 1 }
remove_track: _remove_track end { 1 }
rewind: _rewind end { 1 }
save_state: _save_state end { 1 }
send: _send end { 1 }
set_track: _set_track end { 1 }
set_version: _set_version end { 1 }
setpos: _setpos end { 1 }
show_chain_setup: _show_chain_setup end { 1 }
show_effects: _show_effects end { 1 }
show_io: _show_io end { 1 }
show_track: _show_track end { 1 }
show_tracks: _show_tracks end { 1 }
solo: _solo end { 1 }
source: _source end { 1 }
start: _start end { 1 }
stereo: _stereo end { 1 }
stop: _stop end { 1 }
to_mark: _to_mark end { 1 }
unity: _unity end { 1 }
unmemoize: _unmemoize end { 1 }
unmute: _unmute end { 1 }
vol: _vol end { 1 }
);

# we redirect STDERR to shut up noisy Parse::RecDescent
# but don't see "Bad grammar!" message when P::RD fails
# to process the grammar

#open SAVERR, ">&STDERR";
#open STDERR, ">/dev/null" or die "couldn't redirect IO";
$parser = new Parse::RecDescent ($grammar) or croak "Bad grammar!\n";
#close STDERR;
#open STDERR, ">&SAVERR";

@help_topic = ( undef, qw(   
                    project
                    track
                    chain_setup
                    transport
                    marks
                    effects
                    group
                    mixdown
                    prompt 

                ) ) ;

%help_topic = (

help => <<HELP,
   help <command>          - show help for <command>
   help <fragment>         - show help for commands matching /<fragment>/
   help <ladspa_id>        - invoke analyseplugin for info on a LADSPA id
   help <topic_number>     - list commands under <topic_number> 
   help <topic_name>       - list commands under <topic_name> (lower case)
   help yml                - browse command source file
HELP

project => <<PROJECT,
   load_project, load        - load an existing project 
   project_name, pn          - show the current project name
   create_project, create    - create a new project directory tree 
   get_state, recall, retrieve, restore  - retrieve saved settings
   save_state, keep, save    - save project settings to disk
   exit, quit                - exit program, saving state 
PROJECT

chain_setup => <<SETUP,
   arm                       - generate and connect chain setup    
   show_setup, show          - show status, all tracks
   show_chain_setup, chains  - show Ecasound Setup.ecs file
SETUP
track => <<TRACK,
   Most of the Track related commands operate on the 'current
   track'. To cut volume for a track called 'sax',  you enter
   'sax mute' or 'sax; mute'. The first part of the
   command sets a new current track. You can also specify a
   current track by number,  i.e.  '4 mute'.

   add_track, add            -  create one or more new tracks
                                example: add sax; r3 
                                    (record sax from input 3) 
                                example: add piano; r synth
                                    (record piano from JACK client "synth") 

   show_tracks, show, tracks -  show status of all tracks
                                and group settings

   show_track, sh            -  show status of current track,
                                including effects, versions, 
                                modifiers,  "sax; sh"

   stereo                    -  set track width to 2 channels

   mono                      -  set track width to 1 channel

   solo                      -  mute all tracks but current track

   all, nosolo               -  return to pre-solo status

 - channel inputs and outputs 

   source, src, r            -  set track source

                                sax r 3 (record from soundcard channel 3) 

                                organ r synth (record from JACK client "synth")

                             -  with no arguments returns current signal source

   send, out, m, aux         -  create an auxiliary send, argument 
                                can be channel number or JACK client name

                             -  currently one send allowed per track

                             -  not needed for most setups
 - version 

   set_version, version, ver, n  -  set current track version    

 - rw_status

   rec                     -  set track to REC  
   mon                     -  set track to MON
   off, z                  -  set track OFF (omit from setup)

 - vol/pan 

   pan, p                  -  get/set pan position
   pan_back, pb            -  restore pan after pr/pl/pc  
   pan_center, pc          -  set pan center    
   pan_left, pl            -  pan track fully left    
   pan_right, pr           -  pan track fully right    
   unity                   -  unity volume    
   vol, v                  -  get/set track volume    
                              sax vol + 20 (increase by 20)
                              sax vol - 20 (reduce by 20)
                              sax vol * 3  (multiply by 3)
                              sax vol / 2  (cut by half) 
   mute, c, cut            -  mute volume 
   unmute, uncut, cc       -  restore muted volume

 - chain object modifiers

   mod, mods, modifiers    - show or assign select/reverse/playat modifiers
                             for current track
   nomod, nomods, 
   nomodifiers             - remove all modifiers from current track

 - signal processing

   ecanormalize, normalize - run ecanormalize on current track version
   ecafixdc, fixdc         - run ecafixdc on current track version

TRACK

transport => <<TRANSPORT,
   start, t           -  Start processing
   stop, s            -  Stop processing
   rewind, rw         -  Rewind  some number of seconds, i.e. rw 15
   forward, fw        -  Forward some number of seconds, i.e. fw 75
   setpos, sp         -  Set the playback head position, i.e. setpos 49.2
   getpos, gp         -  Get the current head position 

   loop_enable, loop  -  loop playback between two points
                         example: loop 5.0 200.0 (positions in seconds)
                         example: loop start end (mark names)
                         example: loop 3 4       (mark numbers)
   loop_disable, 
   noloop, nl         -  disable looping

   preview            -  start engine with WAV recording disabled
                         (for mic check, etc.) Release with
                         stop/arm.

   doodle             -  start engine with live inputs only.
                         Like preview but MON tracks are
                         excluded, as are REC tracks with
						 identical sources. Release with
                         stop/arm.
                         
TRANSPORT

marks => <<MARKS,
   list_marks, lm     - list marks showing index, time, name
   next_mark, nm      - jump to next mark 
   previous_mark, pm  - jump to previous mark 
   name_mark, nom     - give a name to current mark 
   to_mark, tom       - jump to a mark by name or index
   remove_mark, rmm   - remove current mark
MARKS

effects => <<EFFECTS,
    
   ladspa-register, lrg       - list LADSPA effects
   preset-register, prg       - list Ecasound presets
   ctrl-register, crg         - list Ecasound controllers 
   add_effect,    fxa, afx    - add an effect to the current track
   insert_effect, ifx, fxi    - insert an effect before another effect
   modify_effect, fxm, mfx    - set, increment or decrement an effect parameter
   remove_effect, fxr, rfx    - remove an effect or controller
   add_controller, acl        - add an Ecasound controller
EFFECTS

group => <<GROUP,
   group_rec, grec, R         - group REC mode 
   group_mon, gmon, M         - group MON mode 
   group_off, goff, MM        - group OFF mode 
   group_version, gver, gv    - select default group version 
                              - used for switching among 
                                several multitrack recordings
   bunch, bn                  - name a group of tracks
                                e.g. bunch strings violins cello bass
                                e.g. bunch 3 4 6 7 (track indexes)
   for                        - execute command on several tracks 
                                or a bunch
                                example: for strings; vol +10
                                example: for drumkit congas; mute
                                example: for all; n 5 (version 5)
                                example: for 3 5; vol * 1.5
                
GROUP

mixdown => <<MIXDOWN,
   mixdown, mxd                - enable mixdown 
   mixoff,  mxo                - disable mixdown 
   mixplay, mxp                - playback a recorded mix 
MIXDOWN

prompt => <<PROMPT,
   At the command prompt, you can enter several types
   of commands:

   Type                        Example
   ------------------------------------------------------------
   Nama commands               load somesong
   Ecasound commands           cs-is-valid
   Shell expressions           ! ls
   Perl code                   eval 2*3     # no need for 'print'

PROMPT
    
);
# print values %help_topic;

$help_screen = <<HELP;

Welcome to Nama help

The help command ('help', 'h') can take several arguments.

help <command>          - show help for <command>
help <fragment>         - show help for all commands matching /<fragment>/
help <topic_number>     - list commands under topic <topic_number> below
help yml                - browse the YAML command source (authoritative)

help is available for the following topics:

1  Project
2  Track
3  Chain setup
4  Transport
5  Marks
6  Effects
7  Group control
8  Mixdown
9  Command prompt 
10 All
HELP


# we use the following settings if we can't find config files

$default = <<'FALLBACK_CONFIG';
#
#
#         Nama Configuration file

#         Notes

#         - This configuration file is distinct from
#           Ecasound's configuration file .ecasoundrc . 
#           In most instances the latter is not required.

#        - The format of this file is YAMLish, preprocessed to allow
#           comments.
#
#        - A value _must_ be supplied for each 'leaf' field.
#          For example "mixer_out_format: cd-stereo"
#
#        - A value must _not_ be supplied for nodes, i.e.
#          'device:'. The value for 'device' is the entire indented
#          data structure that follows in subsequent lines.
#
#        - Indents are significant, two spaces indent for
#          each new level of branching
#
#        - Use the tilde symbol '~' to represent a null value
#

# project root directory

# all project directories (or their symlinks) will live here

project_root: ~                  # replaced during first run


# define abbreviations

abbreviations:  
  24-mono: s24_le,1,frequency
  24-stereo: s24_le,2,frequency,i
  cd-mono: s16_le,1,44100
  cd-stereo: s16_le,2,44100,i
  frequency: 44100

# define audio devices

devices: 
  jack:
    signal_format: f32_le,N,frequency
  consumer:
    ecasound_id: alsa,default
    input_format: cd-stereo
    output_format: cd-stereo
  multi:
    ecasound_id: alsa,ice1712
    input_format: s32_le,12,frequency
    output_format: s32_le,10,frequency
  null:
    ecasound_id: null

# ALSA device assignments and formats

capture_device: consumer          # for ALSA/OSS
playback_device: consumer        # for ALSA/OSS
mixer_out_format: cd-stereo      # for ALSA/OSS

# audio file formats

mix_to_disk_format: cd-stereo
raw_to_disk_format: s16_le,N,frequency

# globals for our chain setups

ecasound_globals: "-B auto -r -z:mixmode,sum -z:psr "

# WAVs recorded at the same time get the same numeric suffix

use_group_numbering: 1

# end

FALLBACK_CONFIG

1;
__END__

=head1 NAME

B<Audio::Ecasound::Multitrack> - Perl extensions for multitrack audio processing

B<Nama> - Lightweight multitrack recorder/mixer

=head1 SYNOPSIS

B<nama> [I<options>] [I<project_name>]

=head1 DESCRIPTION

B<Audio::Ecasound::Multitrack> provides class libraries for
tracks and buses, and a track oriented user interface for managing 
runs of the Ecasound audio-processing engine.

B<Nama> is a lightweight recorder/mixer application that
configures Ecasound as a single mixer bus.

By default, Nama starts up a GUI interface with a command
line interface running in the terminal window. The B<-t>
option provides a text-only interface for console users.

=head1 OPTIONS

=over 12

=item B<-d> F<project_root>

Use F<project_root> as Nama's top-level directory. Default: $HOME/nama

=item B<-f> F<config_file>

Use F<config_file> instead of default F<.namarc>

=item B<-g>

GUI/text mode (default)

=item B<-t>

Text-only mode

=item B<-c>

Create the named project

=item B<-a>

Save and reload ALSA mixer state using alsactl

=item B<-m>

Don't load saved state

=back

=head1 CONTROLLING ECASOUND

Ecasound is configured through use of I<chain setups>.
Chain setups are central to controlling Ecasound.  
Nama generates appropriate chain setups for 
recording, playback, and mixing covering a 
large portion of Ecasound's functionality.

Commands for audio processing with Nama/Ecasound fall into
two categories: I<static commands> that influence the chain
setup and I<dynamic commands> that influence the realtime
behavior of the audio processing engine.

=head2 STATIC COMMANDS

Setting the REC/MON/OFF status of a track by the
C<rec>/C<mon>/C<off> commands, for example,
determine whether that track will be included next time the
transport is armed, and whether the corresponding audio
stream will be recorded to a file or played back from an
existing file. Other static commands include C<loop_enable>
and C<stereo>/C<mono> which select track width.

=head2 CONFIGURING THE ENGINE

The C<arm> command generates an Ecasound chain setup based
on current settings and uses it to configure the audio
processing engine.  Remember to issue this command as the
last operation before starting the engine. This will help
ensure that the processing run accomplishes what you intend.

=head2 DYNAMIC COMMANDS

Once a chain setup is loaded and the engine launched,
another subset of commands controls the audio processing
engine. Commonly used I<dynamic commands> include C<start>
and C<stop>;  C<forward>, C<rewind> and C<setpos> commands
for repositioning the playback head; and C<vol> and C<pan>
for adjusting effect parameters.  Effect parameters may be
adjusted at any time. Effects may be added  audio
processing, however the additional latency will cause an
audible click.

=head1 DIAGNOSTICS

Once a chain setup has generated by the C<arm> commands, it
may be inspected with the C<chains> command.  The C<showio>
command displays the data structure used to generate the
chain setup. C<dump> displays data for the current track.
C<dumpall> shows the state of most program objects and
variables (identical to the F<State.yml> file created by the
C<save> command.)

=head1 Tk GRAPHICAL UI 

Invoked by default, the Tk interface provides all
functionality on two panels, one for general control, the
second for effects. 

Logarithmic sliders are provided automatically for effects
with hinting. Text-entry widgets are used to enter
parameters for effects where hinting is not available.

After issuing the B<arm> or B<connect> commands, the GUI
title bar and time display change color to indicate whether
the upcoming operation will include live recording (red),
mixdown only (yellow) or playback only (green).  Live
recording and mixdown can take place simultaneously.

The text command prompt appears in the terminal window
during GUI operation. Text commands may be issued at any
time.

=head1 TEXT UI

Press the I<Enter> key if necessary to get the following command prompt.

=over 12

C<nama ('h' for help)E<gt>>

=back

You can enter Nama and Ecasound commands directly, Perl code
preceded by C<eval> or shell code preceded by C<!>.

Multiple commands on a single line are allowed if delimited
by semicolons. Usually the lines are split on semicolons and
the parts are executed sequentially, however if the line
begins with C<eval> or C<!> the entire line will be given to
the corresponding interpreter.

You can access command history using up-arrow/down-arrow.

Type C<help> for general help, C<help command> for help with
C<command>, C<help foo> for help with commands containing
the string C<foo>. C<help_effect foo bar> lists all 
plugins/presets/controller containing both I<foo> and
I<bar>. Tab-completion is provided for Nama commands, Ecasound-iam
commands, plugin/preset/controller names, and project names.

=head1 TRACKS

Ecasound deals with audio processing at
the level of devices, files, and signal-processing
chains. Nama implements tracks to provide a
level of control and convenience comparable to 
many digital audio workstations.

Each track has a descriptive name (i.e. vocal) and an
integer track-number assigned when the track is created.

=head2 VERSION NUMBER

Multiple WAV files can be recorded for each track. These are
identified by a version number that increments with each
recording run, i.e. F<sax_1.wav>, F<sax_2.wav>, etc.  All
files recorded at the same time have the same version
numbers. 

Version numbers for playback can be selected at the group
and track level. By setting the group version number to 5,
you can play back the fifth take of a song, or perhaps the
fifth song of a live recording session. 

The track's version setting, if present, overrides 
the group setting. Setting the track version to zero
restores control of the version number to the default
group setting.

=head2 REC/MON/OFF

REC/MON/OFF status is used to generate the chain setup
for an audio processing run.

Each track, including Master and Mixdown, has its own
REC/MON/OFF setting and displays its own REC/MON/OFF status.
The Tracker group, which includes all user tracks, also has
REC, MON and OFF settings. These provides a convenient way
to control the behavior of all user tracks.

As the name suggests, I<REC> status indicates that a track
is ready to record a WAV file. You need to set both track and
group to REC to source an audio stream from JACK or the
soundcard.

I<MON> status indicates an audio stream available from disk.
It requires a MON setting for the track or group as well as
the presence of file with the selected version number.

I<OFF> status means that no audio is available for the track
from any source.  A track with no recorded WAV files 
will show OFF status, even if set to MON.

An OFF setting for the track or group always results in OFF
status. A track with OFF status will be excluded from the
chain setup. (This setting is distinct from the action of
the C<mute> command, which sets the volume of the track to
zero.)

All user tracks belong to the Tracker group, which has a
group REC/MON/OFF setting and a default version setting for
the entire group.
 
Setting the group to MON (C<group_monitor> or C<gmon>)
forces user tracks with a REC setting to MON status if a WAV
file is available to play, or OFF status if no audio stream
is available. 

The group MON mode triggers automatically after a recording
has created new WAV files.

The group OFF setting (text command B<group_off>)
excludes all user tracks from the chain setup, and is
typically used when playing back mixdown tracks.  The
B<mixplay> command sets the Mixdown group
to MON and the Tracker group to OFF.

The Master bus has only MON/OFF status. Setting REC status
for the Mixdown bus has the same effect as issuing the
B<mixdown> command. (A C<start> command must be issued for
mixdown to commence.)

=head1 BUGS AND LIMITATIONS

Several functions are available only through text commands.

=head1 EXPORT

None by default.

=head1 AVAILABILITY

CPAN, for the distribution.

cpan Tk
cpan Audio::Ecasound::Multitrack

Pull source code using this command: 

C<git clone git://github.com/bolangi/nama.git>

Build instructions are contained in the F<README> file.

=head1 AUTHOR

Joel Roth, E<lt>joelz@pobox.comE<gt>


# ------------  Bus --------------------

package Audio::Ecasound::Multitrack::Bus;
our $VERSION = 1.0;
use strict;
our ($debug);
$debug = 0;
use Carp;
our @ISA;
use Audio::Ecasound::Multitrack::Object qw(	name
						groups
						tracks 
						rules
						
						);

sub new {
	my $class = shift;
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	return bless { 
		tracks => [], 
		groups => [], 
		rules  => [],
		@_ }, $class; 
}


		
sub apply {
	
	#print join " ", map{ ref $_ } values %Audio::Ecasound::Multitrack::Rule::by_name; exit;
	my $bus = shift;
	$debug and print q(applying rules for bus "), $bus->name, qq("\n);
	$debug and print "bus name: ", $bus->name, $/;
	$debug and print "groups: ", join " ", @{$bus->groups}, $/;
	$debug and print "rules: ", join " ", @{$bus->rules}, $/;
	my @track_names = (@{$bus->tracks}, 

		map{ $debug and print "group name: $_\n";
			#print join " ", "keys:", keys( %Audio::Ecasound::Multitrack::Group::by_name), $/;
			my $group = $Audio::Ecasound::Multitrack::Group::by_name{$_}; 
			#print "group validated: ", $group->name, $/;
			#print "includes: ", $group->tracks, $/;
			$group->tracks 
								}  @{ $bus->groups }

	);
	$debug and print "tracks: ", join " ", @track_names, $/;
	my @tracks = map{ $Audio::Ecasound::Multitrack::Track::by_name{$_} } @track_names; 

	map{ my $rule_name = $_;
		$debug and print "apply rule name: $rule_name\n"; 
		my $rule = $Audio::Ecasound::Multitrack::Rule::by_name{$_};
		#print "rule is type: ", ref $rule, $/;
		$debug and print "condition: ", $rule->condition, $/;

		map{ my $track = $_; # 
			my $n = $track->n;
			$debug and print "track ", $track->name, " index: $n\n";
			my $key1 = deref_code($rule->input_type, $track);
			my $key2 = deref_code($rule->input_object, $track) ;
			my $chain_id = deref_code($rule->chain_id, $track) ;
			my $rec_status = $track->rec_status;
			my $condition_met = deref_code($rule->condition, $track);

			$debug and print "chain_id: $chain_id, rec_status: $rec_status, condition: $condition_met,  input key1: $key1, key2: $key2\n";
			if ( 
				$track->rec_status ne 'OFF' 
					and $rule->status
					and ( 		$rule->target =~ /all|none/
							or  $rule->target eq $track->rec_status)
					and $condition_met
						
						)  {

				defined $rule->input_type and
					push @{ $Audio::Ecasound::Multitrack::inputs{ $key1 }->{ $key2 } }, $chain_id ;

				$key1 = deref_code($rule->output_type, $track);
				$key2 = deref_code($rule->output_object, $track) ;
			$debug and print "chain_id: $chain_id, rec_status: $rec_status, condition: $condition_met, output key1: $key1, key2: $key2\n";

				defined $rule->output_type and
					push @{ $Audio::Ecasound::Multitrack::outputs{ $key1 }->{ $key2 } }, $chain_id;
			# add intermediate processing
		
		my ($post_input, $pre_output);
		$post_input = deref_code($rule->post_input, $track) 
			if defined $rule->post_input;
		$pre_output = deref_code($rule->pre_output, $track) 
			if defined $rule->pre_output;
		$debug and print "pre_output: $pre_output, post_input: $post_input\n";
		$Audio::Ecasound::Multitrack::post_input{$chain_id} .= $post_input if defined $post_input;
		$Audio::Ecasound::Multitrack::pre_output{$chain_id} .= $pre_output if defined $pre_output;
			}

		} @tracks;
	} @{ $bus->rules }; 
}
# the following is utility code, not an object method

sub deref_code {
	my ($value, $track) = @_;
	my $type = ref $value ? ref $value : "scalar";
	my $tracktype = ref $track;
	#print "found type: $type, value: $value\n";
	#print "found type: $type, tracktype: $tracktype, value: $value\n";
	if ( $type  =~ /CODE/){
		 $debug and print "code found\n";
		$value = &$value($track);
		 $debug and print "code value: $value\n";
		 $value;
	} else {
		$debug and print "scalar value: $value\n"; 
		$value }
}
#$ perl -e 'my $foo = sub{ print "foo: @_" }; my $a = 3; &$foo($a)'
# foo: 3$ 

package Audio::Ecasound::Multitrack::MasterBus; # subclass
our @ISA = 'Audio::Ecasound::Multitrack::Bus';
use Audio::Ecasound::Multitrack::Object qw(	name
						groups
						tracks 
						rules
						
						);

sub apply {
	
	my $bus = shift;
	$debug and print q(applying rules for bus "), $bus->name, qq("\n);
	map{ my $rule = $_;
		print "rule: $rule\n";
		$rule = $Audio::Ecasound::Multitrack::Rule::by_name{$rule};
		my $track = "dummy";
			my $key1 = Audio::Ecasound::Multitrack::Bus::deref_code($rule->input_type);
			my $key2 = Audio::Ecasound::Multitrack::Bus::deref_code($rule->input_object) ;
			my $chain_id = Audio::Ecasound::Multitrack::Bus::deref_code($rule->chain_id) ;
			my $rec_status = $track->rec_status;
			my $condition_met = Audio::Ecasound::Multitrack::Bus::deref_code($rule->condition);

			$debug and print "chain_id: $chain_id, rec_status: $rec_status, condition: $condition_met,  input key1: $key1, key2: $key2\n";
			if(	$condition_met and $rule->status and $rule->target =~ /all|none/ )  {

				defined $rule->input_type and
					push @{ $Audio::Ecasound::Multitrack::inputs{ $key1 }->{ $key2 } }, $chain_id ;

				$key1 = Audio::Ecasound::Multitrack::Bus::deref_code($rule->output_type);
				$key2 = Audio::Ecasound::Multitrack::Bus::deref_code($rule->output_object) ;
				$debug and print "chain_id: $chain_id, rec_status: $rec_status, condition: $condition_met, output key1: $key1, key2: $key2\n";

				defined $rule->output_type and
					push @{ $Audio::Ecasound::Multitrack::outputs{ $key1 }->{ $key2 } }, $chain_id;
				# add intermediate processing
		
				my ($post_input, $pre_output);
				$post_input = Audio::Ecasound::Multitrack::Bus::deref_code($rule->post_input, $track) 
					if defined $rule->post_input;
				$pre_output = Audio::Ecasound::Multitrack::Bus::deref_code($rule->pre_output, $track) 
					if defined $rule->pre_output;
				$debug and print "pre_output: $pre_output, post_input: $post_input\n";
				$Audio::Ecasound::Multitrack::post_input{$chain_id} .= $post_input if defined $post_input;
				$Audio::Ecasound::Multitrack::pre_output{$chain_id} .= $pre_output if defined $pre_output;

			} 
			
		} @{ $bus->rules }; 
}





# ------------  Rule  --------------------
	
package Audio::Ecasound::Multitrack::Rule;
use Carp;
use vars qw($n %by_name @by_index %rule_names);
$n = 0;
@by_index = ();	# return ref to Track by numeric key
%by_name = ();	# return ref to Track by name
%rule_names = (); 
use Audio::Ecasound::Multitrack::Object qw( 	name
						chain_id

						target 
					 	condition		

						output_type
						output_object
						output_format

						input_type
						input_object

						post_input
						pre_output 

						status ); # 1 or 0

# chain_id, depends_on, apply_inputs and apply_outputs are
# code refs.
						
#target: REC | MON | chain_id | all | none

sub new {
	# returns a reference to an object that is indexed by
	# name and by an assigned index
	#
	# The indexing is bypassed and an object returned 
	# if an index n is supplied as  a parameter
	
	my $class = shift;
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	croak "rule name already in use: $vals{name}\n"
		 if $rule_names{$vals{name}}; # null name returns false
	$n++;
	my $object = bless { 	
		name 	=> "Rule $n", # default name
		target  => 'all',     # default target
		condition => 1, 	# apply by default
					@_,  			}, $class;

	$rule_names{$vals{name}}++;
	#print "previous rule count: ", scalar @by_index, $/;
	#print "n: $n, name: ", $object->name, $/;
	$by_index[$n] = $object;
	$by_name{ $object->name } = $object;
	$object;
	
}

sub all_rules { @by_index[1..scalar @by_index - 1] }

sub dump{
	my $rule = shift;
	print "rule: ", $rule->name, $/;
}

### subclass

package Audio::Ecasound::Multitrack::MixBus;
our @ISA = 'Audio::Ecasound::Multitrack::Bus';
sub apply {} ; ## TODO 

1;

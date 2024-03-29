package Audio::Ecasound::Multitrack::Wav;
our $VERSION = 1.0;
our @ISA; 
use Audio::Ecasound::Multitrack::Object qw(name active dir);
use warnings;
use Audio::Ecasound::Multitrack::Assign qw(:all);
use Memoize qw(memoize unmemoize);
no warnings qw(uninitialized);
use Carp;

sub get_versions {
	my $self = shift;
	my ($sep, $ext) = qw( _ wav );
	my ($dir, $basename) = ($self->dir, $self->basename);
#	print "dir: ", $self->dir(), $/;
#	print "basename: ", $self->basename(), $/;
	$debug and print "getver: dir $dir basename $basename sep $sep ext $ext\n\n";
	my %versions = ();
	for my $candidate ( candidates($dir) ) {
		$debug and print "candidate: $candidate\n\n";
		$candidate =~ m/^ ( $basename 
		   ($sep (\d+))? 
		   \.$ext )
		   $/x or next;
		$debug and print "match: $1,  num: $3\n\n";
		$versions{ $3 || 'bare' } =  $1 ;
	}
	$debug and print "get_version: " , Audio::Ecasound::Multitrack::yaml_out(\%versions);
	%versions;
}

sub candidates {
	my $dir = shift;
	$dir =  File::Spec::Link->resolve_all( $dir );
	opendir WD, $dir or die "cannot open $dir: $!";
	my @candidates = readdir WD;
	closedir WD;
	@candidates = grep{ ! (-s join_path($dir, $_) == 44 ) } @candidates;
	#$debug and print join $/, @candidates;
	@candidates;
}

sub targets {
	
	my $self = shift; 

#	$Audio::Ecasound::Multitrack::debug2 and print "&targets\n";
	
		my %versions =  $self->get_versions;
		if ($versions{bare}) {  $versions{1} = $versions{bare}; 
			delete $versions{bare};
		}
	$debug and print "\%versions\n================\n", yaml_out(\%versions);
	\%versions;
}

	
sub versions {  
#	$Audio::Ecasound::Multitrack::debug2 and print "&versions\n";
	my $self = shift;
	[ sort { $a <=> $b } keys %{ $self->targets} ]  
}

sub last { 
	my $self = shift;
	pop @{ $self->versions} }


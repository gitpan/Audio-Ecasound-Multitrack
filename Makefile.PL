use inc::Module::Install;

         # Define metadata
         name                'Audio-Ecasound-Multitrack';
		 all_from            'lib/Audio/Ecasound/Multitrack.pm';
		 license_from        'README';
		 install_script      'script/nama'; 

         # Specific dependencies
		
requires
		Audio::Ecasound => 0,
		Carp => 0,
		Cwd => 0,
		Data::Rmap => 0,
		Data::YAML => 0,
		Event => 0,
		File::Find::Rule => 0,
		File::Spec::Link => 0,
		Storable => 0,
		Getopt::Std => 0,
		IO::All => 0,
		Module::Load::Conditional => 0,
		Parse::RecDescent => 0,
		Storable => 0,
		Term::ReadLine => 0,
		Term::ReadLine::Gnu => 0,
		Text::Format => 0,
		Time::HiRes => 0,
		;
        WriteAll;

package WeBWorK::ContentGenerator::Tutor::Tutorial;

=pod
=begin Tutorial
        _ATTR tutorialID    $string tutorialID
        _ATTR courseName    $string CourseName
        _ATTR setName       $string setName
        _ATTR problemID     $string problemID
=end Tutorial
=cut
sub new {
	
	my @tutor = @_;
	
    my $self = $tutor[0];
    my $tutSet = $tutor[1];
    
    $self->{tutorialID} = $tutSet->user_id;
    $self->{forSourseName} = $tutSet->courseName;
    $self->{forSetName} = $tutSet->last_name;
    $self->{forProblemID} = $tutSet->email_address;
    
    return $self;
}

1;

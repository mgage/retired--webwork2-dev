package WeBWorK::ContentGenerator::RECORD;


use CGI qw(:standard);
use CGI::Carp qw(warningsToBrowser fatalsToBrowser);
use Fcntl qw(:flock :seek);
use Exporter;

our @EXPORT    = ();
our @EXPORT_OK = qw( removeTutorialFlag
                     writeT
                     writeDATALOG
                     flagUser
                     hasTutorialFlag     );

our $flagTable = '/opt/webwork/webwork2/lib/WeBWorK/ContentGenerator/Tutor/Tables/flagTable.data';
our $tutorTable = '/opt/webwork/webwork2/lib/WeBWorK/ContentGenerator/Tutor/Tables/tutorTable.data';
our $logTable = '/opt/webwork/webwork2/lib/WeBWorK/ContentGenerator/Tutor/Tables/log.data';
our $testDataW = '/opt/webwork/webwork2/lib/WeBWorK/ContentGenerator/Tutor/Tables/tDebug.data';

sub testTutorialName{
	 
	 my $name = "Beya Adamu";
	 return $name;
}

sub writeT{
	
	my ($writeTo, @flagData) = @_;
	my ($userID, $setID, $problemID, $file) = @flagData;
	
	if( $writeTo eq "flagTable"){		       
        open(DAT, ">>$flagTable") or die("Couldn't open $flagTable: $!");        
        print DAT "USERNAME=$userID".
                  "&SETID=$setID".
                  "&PROBLEMID=$problemID".
                  "&PROBLEMSOURCE=$file".
        close(DAT);
        return 1;
    }
	return 0;
}

sub getTutorialSet{
	
	my ($setID) = @_;
	my $tutorialSet = "";
	
	open(TABLE, $tutorTable) or die "Error opening $tutrTable: $!";		
	while(<TABLE>){
		chomp;		
		my %line = split(/=/,$_);		
		foreach my $k (keys %line) {
			if($k eq "$setID"){
				$tutorialSet = $line{$k};
			}
		}		
	}
	close (TABLE); 
	return $tutorialSet; 	
}

sub flagUser{
	
	return writeT(@_);
}

sub removeTutorialFlag{
	
	my ($userID, $courseName, $setID, $problemID) = @_;
	my @newData;
	my $removed = 0;
	
    ##################################################################################
	## OPEN FLAG TABLE AND STORE DATA TO TEMP STORAGE AND CLOSE FILE		
	open(FT, "$flagTable") or die "CAN NOT OPEN $flagTable.";	
	my @data = <FT>;
	close FT;
    ##################################################################################
	
	##################################################################################
	## FIND USER'S DATA, AND REMOVE FLAG FOR THE PROBLEM VERSION			
	my %keyValue = ();
	foreach my $line (@data){
		
		$line = trim($line);
		chomp($line);
		my @rawData = split(/&/,$line);
		
		foreach my $n (@rawData){
			my($key,$value) = split(/=/,$n);	
			$keyValue{$key} = $value;
			
	
		}
		if( ($keyValue{USERNAME} eq "$userID") && ($keyValue{SETID} eq $setID)&&
		    ($keyValue{COURSENAME} eq "$courseName") && ($keyValue{PROBLEMID} == $problemID)){				
             $removed = 1;				
		}		
		#if( ($keyValue{USERNAME} eq "$userID") && ($keyValue{SETID} eq $setID) &&
		#    ($keyValue{COURSENAME} eq "$courseName") && ($keyValue{PROBLEMID} == $problemID)){				
        #     $removed = 1;				
		#}
		else {
			push(@newData, "$line\n");
		}
	}
	if($removed == 1){
		
		##################################################################################
		# WRITE NEW DATA AGAIN AFTER REMOVING USER'S FLAG LINE
		open(TABLE, ">$flagTable") or die "Error writing to file $flagTable: $!";
		print TABLE "@newData";
		close TABLE;
		return 1;
		##################################################################################

	}
	else{
		
		##################################################################################
		# WRITE NEW DATA AGAIN AFTER REMOVING USER'S FLAG LINE
		print "ERR:";
		return 0;
		##################################################################################

	}

}


sub getFlaggedSetName{

	my @userID = @_;
	my @problemVersion = ();
	my %keyValue = ();

	open(TABLE, "$flagTable") or die "Error opening $flagTable: $!";	
	my @data = <TABLE>;
	close TABLE;
	
	
	foreach my $read (@data){
		
		chomp($read);
		my @variables = split(/&/,$read);
		
		foreach my $values (@variables){
			my $tValues = trim($values);
			my ($key, $value) = split(/=/,$tValues);
			trim($key);
			
			$keyValue{$key} = $value;

		}
	
		if($keyValue{USERNAME} eq "$userID"){
            push(@problemVersion, "$keyValue{SETID}");
            return @problemVersion
		}				
	}
	return @problemVersion;
	
}



sub getFlaggedProblems{

	my @userID = @_;
	my @problemVersion = ();
	my %keyValue = ();

	open(TABLE, "$flagTable") or die "Error opening $flagTable: $!";	
	my @data = <TABLE>;
	close TABLE;
	
	
	foreach my $read (@data){
		
		chomp($read);
		my @variables = split(/&/,$read);
		
		foreach my $values (@variables){
			my $tValues = trim($values);
			my ($key, $value) = split(/=/,$tValues);
			trim($key);
			
			$keyValue{$key} = $value;

		}
	
		if($keyValue{USERNAME} eq "$userID"){
            push(@problemVersion, "$keyValue{SETID}");
		}				
	}
	return @problemVersion;
	
}

sub hasTutorialFlag{	
	
	my @userID = @_;
	my $flag = 0;
    open(DAT, "$flagTable") or die "Error opening $flagTable: $!";	
    my @data = <DAT>;	
    close DAT;

	foreach my $line (@data){
		$line = trim($line);
		chomp($line);
		my @rawData = split(/&/,$line);
		foreach my $n (@rawData){
			my($key,$value) = split(/=/,$n);	
			if($key eq "USERNAME" && $value eq "@userID"){
				$flag++;
			}
		}
	}
	return $flag;
}

sub getUserTutorial{
	
	my ($userID, $setID) = @_;
	my @tutorialSet = ();
	
	###############################################################################################
	### GET TUTORIAL SET
	open(TABLE, "$flagTable") or die "Error opening $tutrTable: $!";	
	my @data = <TABLE>;
	close TABLE;

    my %keyVal = ();
	
	foreach my $line (@data){
		chomp($line);
		my $line = trim($line);
		my @variables =  split(/&/, $line);
		foreach my $values(@variables){
			my ($key,$value) = split(/=/,$values);
			$keyVal{$key} = $value;
		}		
		if(($keyVal{userID} eq $userID) && ($keyVal{problemVersion} eq "$problemVersion")){
			push(@tutorialSet, $keyVal{tutorialSet})	
		}
	}
	print "    >>>GETUSERTUTORIAL.RESULTS(|";
	foreach my $set (@tutorialSet){
		print "$set|"
	}
	print ")\n";
	return @tutorialSet;	
}

sub trim($) {
	my $string = shift;
	#print "TRIM .$string\n";
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	#print "TRIM .$string\n";
	return $string;
}

sub writeLOG{	
	
	my (@data) = @_;
	open(LOG, ">>$logTable") or die("Couldn't open $logTable: ");
    foreach my $line (@data){
        print LOG "$line";	
    }
    close(LOG);

	return 1;
}

sub readTable{
	
	my $fileToRead = @_;
	
	open(DAT, "$fileToRead") or die "Error opening (RECORD::hasTutorial) $flagTable: $!";	
    my @data = <DAT>;	
    close DAT;
    
    return @data;
}
1;

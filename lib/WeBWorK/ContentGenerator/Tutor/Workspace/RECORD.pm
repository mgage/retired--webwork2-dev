package WeBWorK::ContentGenerator::RECORD;


use CGI qw(:standard);
use CGI::Carp qw(warningsToBrowser fatalsToBrowser);
use Fcntl qw(:flock :seek);
use Exporter;

our @EXPORT    = ();
our @EXPORT_OK = qw( testTutorialName
                     writeT
                     writeDATALOG     );

our $flagTable = '/opt/webwork/webwork2/lib/WeBWorK/ContentGenerator/Tutor/Tables/flagTable.data';
our $tutrTable = '/opt/webwork/webwork2/lib/WeBWorK/ContentGenerator/Tutor/Tables/tutorTable.data';
our $debgTabqle = '/opt/webwork/webwork2/lib/WeBWorK/ContentGenerator/Tutor/Tables/log.data';
our $testDataW = '/opt/webwork/webwork2/lib/WeBWorK/ContentGenerator/Tutor/Tables/tDebug.data';

sub testTutorialName{
	 
	 my $name = "Beya Adamu";
	 return $name;
}

sub writeT{
	
	my ($writeTo, @data) = @_;
	print "    >>>RECORD.WRITE.REQUESTED";
	if($writeTo eq "flagTable"){		
		print ".TO.$writeTo:";			
		if(@data == 4){
			print "(@data)\n";		
			my ($userID,$problemVersion,$tutorialSet,$session) = @data;
			open(DAT, ">>$flagTable") or die("Couldn't open $flagTable: $!");
			my $wFile = "userID=$userID&flag=1&problemVersion=$problemVersion&tutorialSet=$tutorialSet&session=$session";
			print DAT "$wFile\n";
			close(DAT);
			print "    <<<RECORD.WRITE.RESULT.(1)\n";
			return 1;
		}
		else{
			print "    <<<RECORD.WRITE.RESULT.(0)\n";
			return 0;
		}
	}
	if($writeTo eq "debug"){
		print ".TO.$writeTo:  '@data'\n";
		open(DAT, ">>$debgTable") or die("Couldn't open $debgTable: $!");
		print DAT "@data\n";
		close(DAT);
		print "    <<<RECORD.WRITE.RESULT.(1)\n";
		return 1;
	}
	print "    <<<RECORD.WRITE.RESULT.(0)\n";
	return 0;
}

sub getTutorials{
	
	my ($problemVersion) = @_;
	my $tutorialSet = "";
	print "    >>>RECORD.GET.TUTORIAL: ($problemVersion)\n";	
	open(TABLE, "$tutrTable") or die "Error opening $tutrTable: $!";		
	while(<TABLE>){
		chomp;		
		my %line = split(/=/,$_);		
		foreach my $k (keys %line) {
			if($k eq "$problemVersion"){
				$tutorialSet = $line{$k};
			}
		}		
	}
	print "    <<<RECORD.GET.TUTORIAL:RESULT: ($tutorialSet)\n";
	return $tutorialSet; 	
}

sub flagUser{
	
	return writeT(@_);
}

sub removeTutorialFlag{
	
	my ($userID, $problemVersion) = @_;
	my @newData;
	my $removed = 0;
	
	##################################################################################
	print "    >>>RECORD.REMOVETUTORIALFLAG:Parameters($problemVersion)\n";
	##################################################################################
	
	##################################################################################
	## OPEN FLAG TABLE AND STORE DATA TO TEMP STORAGE AND CLOSE FILE		
	open(FT, "$flagTable") or die "Error opening $flagTable: $!";	
	my @data = <FT>;
	close FT;
	my $dSize = @data;
	print "      :DATAREAD.COMPLETE::  SIZE: $dSize\n";
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
		if($keyValue{userID} eq "$userID"){					
			if($keyValue{problemVersion} eq "$problemVersion"){
				print "      ::FOUND.|$problemVersion|\n";
				$removed = 1;				
				###########################################################################
				$problemVersion = "OUT";   #COMMENT THIS LINE TO DE-FLAG ALL VERSION FLAGS
				###########################################################################
			}
			else{
				push(@newData, "$line\n");
			}
		}
		else{
			push(@newData, "$line\n");
		}
	}
	if($removed == 1){
		##################################################################################
		# WRITE NEW DATA AGAIN AFTER REMOVING USER'S FLAG LINE
		open(TABLE, ">$flagTable") or die "Error writing to file $flagTable: $!";
		$dSize = @newData;
		print TABLE "@newData";
		close TABLE;
		print "      :DATA.RE-WRITE.COMPLETE::  SIZE OF NEW DATA : $dSize\n";
		print "    <<<REMOVETUTORIALFLAG:RESULT.1\n";
		return 1;
		##################################################################################
		##################################################################################
	}
	else{
		##################################################################################
		# WRITE NEW DATA AGAIN AFTER REMOVING USER'S FLAG LINE
		print "      :(!)NOT.REMOVEDFOUND / NOT.FOUND  |$dSize\n";
		print "    <<<REMOVETUTORIALFLAG:RESULT.Failed - 0\n";
		return 0;
		##################################################################################
		##################################################################################
	}
	
	
		

}

sub getFlaggedProblems{

	my @userID = @_;
	my @problemVersion = ();
	my %keyValue = ();

	print "    >>>RECORD.GETFLAGGEDPROBLEMS(@userID)\n";

	open(TABLE, "$flagTable") or die "Error opening $flagTable: $!";	
	my @data = <TABLE>;
	close TABLE ;
	foreach my $read (@data){
		chomp($read);
		#print "$read\n";
		my @variables = split(/&/,$read);
		foreach my $values (@variables){
			#print ".$values\n";
			my $tValues = trim($values);
			#print ".$tValues\n";
			my ($key, $value) = split(/=/,$tValues);
			trim($key);
			$keyValue{$key} = $value;
			#print" KEY: .$key($value)\n";
		}
		if($keyValue{userID} eq "@userID"){
			#print "FOUND";
			push(@problemVersion, "$keyValue{problemVersion}");
		}
	}
	print "    <<<GETFLAGGEDPROBLEMS.RESULTS(|";
	foreach my $probs (@problemVersion){
		print "$probs|";
	}
	print ")\n";
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
			$keyValue{$key} = $value;		
		}	
		if($keyValue{userID} eq "@userID"){		
			if($keyValue{flag} eq "1"){
				$flag++;
			}
		}
	}
	if($flag > 0){print "YES:";}else{print "NO:"}
	print "$flag)\n";
	return $flag;
}

sub getUserTutorial{
	
	my ($userID, $problemVersion) = @_;
	
	
	my @tutorialSet = ("a33", "a77");
	print "    >>>RECORD.GETUSERTUTORIAL($userID\, $problemVersion)\n";
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

sub writeDATALOG{	
	
	my (@data) = @_;
	open(LOG, ">>$testDataW") or die("Couldn't open $testDataW: $!");
	
	   print LOG "===========================================================================\n";
	      foreach my $line (@data){
		      print LOG "$line\n";	
	      }
	   print LOG "===========================================================================\n";
	
	close(LOG);
	return 1;
}


1;

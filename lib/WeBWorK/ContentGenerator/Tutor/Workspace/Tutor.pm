package WeBWorK::Tutor::Tutor;

################################################################################
#	Tutor Module Experiment
################################################################################

use strict;
use warnings;
use Exporter;
use WeBWorK::Tutor::RECORD;

################################################################################
#	IMPORTANT VARIABLES
#
#   $webworkRoot       directory that contains the WeBWorK distribution
#   $webworkURLRoot    URL that points to the WeBWorK system
#   $pgRoot            directory that contains the PG distribution
#   $courseName        name of the course being used
#
################################################################################


sub new {
	return 1;
}

=head1 MONITOR()
=head1 DESCRIPTION
   
	FIXME: Edit the following for POD

	Method is constructed to monitor quiz scores. Method parameters are  
   	userID, answerScore, session and attempts. Method will evaluate the  
   	answerScore variable to determine score result. 			  		  
   									  							
      	If '0' Score evaluates, 						
	   		-method will call the flag() subroutine to flag user.	 	  
	   		-if flag executes and return a '1',		
				-set $monitorResult to '1' to acknowlege caller
		If '1' Score evaluates						
	   		-method will call the clearFlag() subroutine to clear the flag   
	   		-if clearFlag executes and returns a '1' acknowledgement			
	    		-set $monitorResult to 1 to acknowledge success	
	 
	Method will return monitorResult to caller. A '0' return     
	indicates an error has occured, either from flag() or clearFlag() 	
	subroutines. A '1' monitorResult indicates a success.			 								 

=cut
sub monitor {
	
	###########################################################################################
	# INITIALIZE
	my ($userID, $answerScore, $courseName, $setID, $problemVersion, $problemID, $file) = @_;
	my $result = 0;
	
	###########################################################################################
	# DEBUG
	my @debug = ("MONITORPARAMS", "$userID", "$answerScore", "$problemVersion", "$session");

	###########################################################################################
	# EVALUATE USER'S SCORE
	if($answerScore < 1){
		
		my @flagData = ("$userID", "$courseName", "$setID", "$problemVersion", "$problemID", "$file");
		
		$result= (flag(@flagData)) ? 1 : 0;

	}
	
	###########################################################################################
	# ELSE CLEAR FLAG	
	if($answerScore > 0){
		my @flagData = ("$userID", "$courseName", "$setID", "$problemVersion", "$problemID", "$file");	

		$result = (clearFlag(@flagData)) ? 1 : 0;					
	}
	
	return $result;

}

=head1 FLAG()
=head1 DESCRIPTION
	
	Method will flag a user to a set of tutorials. Method will take a   
	userId, problemVersion, session and attemp variables to process   
	flag request.
	Method will add flag 
						
		-If a tutorial file exists					
			- get Tutorial Set from database for the given problem	 
			- Insert a flag line to the FlagTable in user's table	 
			- Set flagResult a success					
		-Return flagResult

	FIXME: If user is already flagged for the version, skip						
=cut
sub flag {

    my ($userID, $courseName, $setID, $problemVersion, $problemID, $file) = @_;
	my $flagResult = 0;
	my $tutorialSet = ();	

	$tutorialSet = WeBWorK::Tutor::RECORD::getUserTutorial($userID,$setID);
	
	my @flagData("$userID", "$courseName", "$setID", "$problemVersion", "$problemID", "$file"); 
	
	if($tutorialSet){
		$flagResult = WeBWorK::Tutor::RECORD::flagUser("flagTable", @flagData) ? 1 : 0 ;
	}
	
	return $flagResult;

}

sub clearFlag {

    my @flagData = ("$userID", "$courseName", "$setID", "$problemVersion", "$problemID", "$file");
	
	print "    >>TUTOR.CLEARFLAG:Parameters(@_)\n";
	
	if(WeBWorK::Tutor::RECORD::removeTutorialFlag(@flagData)){
		print "    <<TUTOR.CLEARFLAG:RESULT.1\n";
		return 1;		
	}
	return 0;

}
sub getFlaggedSet{
	
############################################################################
############################################################################
##   Method will get the Version ID that system has flagged user with.    
############################################################################
############################################################################
	
	print "    >>TUTOR.GETFLAGGEDVERSION:DATA.(@_)\n";
	my @probVersions = getFlaggedProblems(@_);
	print "    <<GETFLAGGEDVERSION:RESULT (|";
	foreach my $probs (@probVersions){
		print "$probs|";
	}
	print ")\n";
	return @probVersions;
}
sub setTutorial{
	
	
}
sub assignTutorial {
############################################################################
############################################################################						  
##   Method will search and assign a set of tutorials to user’s tutorial  
##   table. Method will assign/associate problem versions to specific set 
##   of tutorial.  Method will be called from instructor console as well  
##   as system.			                                         
############################################################################
############################################################################

	#my ($userID, $session, $problemVersion) = @_;
#
#	print "    >TUTOR.ASSIGN_TUTORIAL:DATA.($_)\n";
#	my $tutorialSet = RECORD -> getTutorials($problemVersion);
#	
#	if($tutorialSet){
#		my @data = q(userID,$problemVersion,$tutorialSet,$session);	
#		return (RECORD -> putTutorialFlag("flagTable", @data)) ? 1 : 0;
#	}
	return 1;
}
sub hasTutorialFlag {
	
	
	## TEST
	writeDATALOG(  " INITIALIZE : HAS FLAG TEST\n",
                            "               URLPATH : ",##$urlpath\n",
                            "               SETNAME : ",##$setName\n",
                            "             USER NAME : ",##$userName\n",
                            "              E.U.NAME : ",##$effectiveUserName\n",
                            "                   KEY : ",##$key\n",                   
                            "     REQUESTED VERSION : ",##$requestedVersion\n",
                            "        LATEST VERSION : ",);##$latestVersion\n"            );
	
	############################################################################
	
	
	
	
	############################################################################
	##   Method will read user’s tutorial table and check if user has a flag 
	##   to a specific problem version.
	##   
	##   PARAMETERS: USERID
	##               			                
	############################################################################
	############################################################################
	## print "    >TUTOR.HASFLAG(@_)\n";
	
	my $flag = hasTutorialFlag(@_);
	
	## print "    <HASFLAG:RESULT($flag)\n";
	
	return $flag;

}
sub getTutorial {

	############################################################################
	############################################################################
	##   Method will locate a tutorial set for a given student and a given  
	##   problem version id.			                    
	############################################################################
	############################################################################
	
	my ($userID, $problemVersion) = @_;
	my @tutorialSet;
	print "    >>TUTOR.GETTUTORIAL($userID, $problemVersion)\n";
	@tutorialSet = getUserTutorial($userID,$problemVersion);
	print "    <<GETTUTORIAL:RESULT(@tutorialSet)\n";
	return @tutorialSet;
	
}
sub getHTML {
	
	############################################################################
	############################################################################
	##   Method will construct an HTML tutorial page suitable for Gateway    
	##   Quiz CGI.
	##
	##   CONSTRUCT THE HTML  /  SWF file of a given Tutorial set
	##   Tutorial will be presented using shockwave discuss w/ Dr. Wangberg)			  				
	############################################################################
	############################################################################
	my ($file) = @_;
	my $html =();
	print "    >>TUTOR.GETHTML($file)\n";
	open(TABLE, "Files/$file") or die "Error opening $file: $!";	
	my @file = <TABLE>;
	close TABLE;
	print "    <<GETHTML.RESULT:\n\n";
	foreach my $text (@file){
		print "      $text";
	}
	print "\n\n";
	return (@file);

}

1;
        

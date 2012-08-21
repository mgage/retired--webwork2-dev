package WeBWorK::ContentGenerator::Tutor;

################################################################################
#	Tutor Module Experiment
################################################################################

use strict;
use warnings;
use WeBWorK::CGI;
use File::Find;
use WeBWorK::DB::Utils qw(initializeUserProblem);
use WeBWorK::Debug;
use WeBWorK::Utils qw(max);
use Exporter;
use WeBWorK::ContentGenerator::RECORD;
use WeBWorK::DB::Record::UserSet;
use WeBWorK::ContentGenerator::Instructor qw(addProblemToSet assignSetToUser);
use WeBWorK::DB::Utils qw(global2user user2global);

use Exporter;

our @EXPORT    = ();
our @EXPORT_OK = qw(  monitor
                      flag
                      assignPracticeAndFinalQuizForUser
                      clearFlag
                      getFlaggedSet
                      setTutorial
                      assignTutorial
                      hasTutorialFlag
                      getTutorial
                      getHTML                 );

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
	
    ### INITIALIZE     
    my ($self, @data) = @_;     
    #my $set       = $self->{set};
    my $problem   = $self->{problem};   
    my ($userID, $answerScore, $setID, $problemID, $file) = @data;
    my @flagData = ("$userID", "$setID", "$problemID", "$file");
    my $result = 0;
    
    ### EVALUATE USER'S SCORE
    #WeBWorK::ContentGenerator::RECORD::writeLOG("LOG=TUTOR.FLAGLOG&MONITOR_SCORES=$answerScore&\n");
    #$answerScore is a string of 0/1, one digit for each part of the problem.
    #We want to assign the entire problem again if there is a 0 anywhere in it,
    #meaning the student had one part of the question wrong.

    #bypass this function!
    #bypass this function if we don't want the system to generate practice sets and final quizzes on the fly.
    return 1;

    return 1 if $setID =~ m/^final/;
    return 1 if $setID =~ m/^Final/;
    return 1 if $setID =~ m/^Practice/;
    return 1 if $setID =~ m/^smallQuiz/;

    if($answerScore =~ m/0/gi ){
        #add problem to practice set for student:
        return (flag($self, @flagData)) ? 1 : 0;
    }
    else {
        #add problem to student's possible final quiz bank
	return (addCorrectProblemToStudentCorrectBank($self, @flagData)) ? 1 : 0;
    }
	    
    #####################################################################################################
    # ELSE CLEAR FLAG	
    #if( $answerScore > 0){
    #   return (clearFlag($self, @flagData)) ? 1 : 0;					
    #}
        
    return 1;

}

sub addCorrectProblemToStudentCorrectBank {
  #Initialize
  my ($self, @data) = @_;
  my $db = $self->{db};
  my $r = $self->r;
  #my $ce = $r->ce;
  my $user = $r->param('user');
  my ($userID, $setID, $problemID, $file) = @data;
  my $urlpath = $r->urlpath;

  #bypass this function
  #return 1;

  my $courseID = $urlpath->arg('courseID');

  my $conceptBank = `php /var/www/html/connecting/workWithWWDB/getConceptGroupFrom_courseID_setID_problemID.php $courseID $setID $problemID`;
  $conceptBank =~ s/^group\://;
  my $sourceFileList = `php /var/www/html/connecting/workWithWWDB/get_n_ValidProblemsFromConceptBank.php 2 $courseID $conceptBank`;
  my @listOfSourceFiles = split(/ /, $sourceFileList);


  my $i;
  for ($i = 1; $i <= 2; $i++) {

    #Add two source files to the final quiz correct banks
    my $correctSetName = $setID . "_" . $userID . "_tcerroc" . $i;

    #my $userSetClass = $ce->{dbLayout}->{set_version}->{record};
    my $newSetRecord = $db->getGlobalSet($correctSetName);

    if (defined($newSetRecord)) {
       #The set already exists.  We're happy!
    }
    else {
      #create the set:
	$newSetRecord = $db->{set}->{record}->new();
	$newSetRecord->set_id($correctSetName);
	$newSetRecord->set_header("");
	$newSetRecord->hardcopy_header("");

	$newSetRecord->open_date(time()+0*60*60*24*7);
	$newSetRecord->due_date(time()+18*60*60*24*7);
	$newSetRecord->answer_date(time()+25*60*60*24*7);

	eval {$db->addGlobalSet($newSetRecord)};
	if ($@) {
	  #problem creating the set $correctSetName
	}
	else {
	  #the set was created!
	}
    }

    my $source = shift(@listOfSourceFiles);
    $newSetRecord = $db->getGlobalSet($correctSetName);
    if (not defined($correctSetName)) {
      #trying to add problems to $correctSetName, which doesn't exist
    }
    else {
      my $newIndex = max($db->listGlobalProblems($correctSetName)) + 1;
      my $problemRecord = $self->WeBWorK::ContentGenerator::Instructor::addProblemToSet(setName => $correctSetName, sourceFile => $source, problemID => $newIndex, value => 1, maxAttempts => -1);
    } 

   
  }
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

    # INITIALIZE      
    my ($self, @data) = @_;
    my $db = $self->{db};
    my $r = $self->r;
    #my $ce = $r->ce;
    my $user = $r->param('user');
    my ($userID, $setID, $problemID, $file) = @data;
    my @flagData = ("$userID", "$setID", "$problemID", "$file");
    my $flagResult = 0;
	my @results;
	my $set_assigned = 0;
	#my $flagSet = $self->{set};
	#my $FlagVersionNumber = $flagSet->version_id;
	#   $FlagVersionNumber++;
    my $urlpath = $r->urlpath;

    #bypass this function if we don't want the system to generate practice sets and final quizzes on the fly.
    return 1;


    my $courseID = $urlpath->arg('courseID');


    ### LOG 
    #WeBWorK::ContentGenerator::RECORD::writeLOG("LOG=TUTOR.FLAGLOG&USERID=". $userID. "&SETID=". $setID."&PROBLEMID=". $problemID. "&" . "SOURCEFILE=". $file. "\n");

    ### IDENTIFY CONCEPT BANK AND GET TUTORIAL SOURCE FILES
    my $conceptBank = `php /var/www/html/connecting/workWithWWDB/getConceptGroupFrom_courseID_setID_problemID.php $courseID $setID $problemID`;
       $conceptBank =~ s/^group\://;  
    my $sourceFileList = `php /var/www/html/connecting/workWithWWDB/get_n_ValidProblemsFromConceptBank.php 3 $courseID $conceptBank`;
    my @listOfSourceFiles = split(/ /, $sourceFileList);

    ### LOG
    #WeBWorK::ContentGenerator::RECORD::writeLOG("LOG=TUTOR.FLAG.FOUND&CONCEPT=". $conceptBank. "&LIST=" );
    #foreach my $source (@listOfSourceFiles) {
    #    WeBWorK::ContentGenerator::RECORD::writeLOG($source. ".");     
    #}
    #WeBWorK::ContentGenerator::RECORD::writeLOG("\n");
    
    
    ### CREATE PRACTICE SET AND INSERT PROBLEM INTO SET
    my $practiceSetName = "Practice_". $userID. "_". $setID ;

    #my $userSetClass = $ce->{dbLayout}->{set_version}->{record};
    my $newSetRecord = $db->getGlobalSet($practiceSetName);
    if (defined($newSetRecord)) {
	#The set already exists.  We're happy!
    }
    else {
	#create the set:
	$newSetRecord = $db->{set}->{record}->new();
	$newSetRecord->set_id($practiceSetName);
	$newSetRecord->set_header("Practice_Homework_Header.pg");
	$newSetRecord->hardcopy_header("");
        #Use this to hardcode a specific date.  Need to know the open date, though.
	#$newSetRecord->open_date(1251619388);  # Sunday, 8/30/2009, at 1am
	#$newSetRecord->due_date(1251619388 + 60*60*24*7*2);  # two weeks later
	#$newSetRecord->answer_date(1251619338 + 60*60*24*7*3); #three weeks later
        $newSetRecord->open_date(time()+0*60*60*24*7);     #now
        $newSetRecord->due_date(time()+2*60*60*24*7);      #due in two weeks.
        $newSetRecord->answer_date(time()+3*60*60*24*7);   #answers available in three weeks

	$newSetRecord->published(1);
	#$newSetRecord->open_date(time()+60*60*24*7);  #in (n)one week
	#$newSetRecord->due_date(time()+60*60*24*7*2); #in two weeks
	#$newSetRecord->answer_date(time()+60*60*24*7*3); #in three weeks

	eval {$db->addGlobalSet($newSetRecord)};
	if ($@) {
	  #problem creating the set $newSetName

	}
	else {
	  #the set was created!
	}
    }
    #my $set = global2user($userSetClass, $db->getGlobalSet($setName));
    #my $set = $db->newSetVersion;
    #   $set->user_id($userID);
    #   $set->psvn('000');
    #   $set->set_id("$practiceSetName");
    #   $set->version_id(0);
  
    ### LOG
    #WeBWorK::ContentGenerator::RECORD::writeLOG("LOG=TUTOR.FLAG.FOUND.SET&SETID=". $set->{set_id}. "\n");    
   
   
    ### ADD PROBLEMS INTO THE SET   
    foreach my $source (@listOfSourceFiles) {
        #my %args = (  setName     => $practiceSetName,
        #              sourceFile  => $source,
        #              value       => 1,
        #              maxAttempts => 10  );
        #WeBWorK::ContentGenerator::Instructor::addProblemToSet($self, %args);
        $newSetRecord = $db->getGlobalSet($practiceSetName);
	if (not defined($practiceSetName)) {
	  #trying to add problems to $practiceSetName, which doesn't exist
	}
	else {
	  my $newIndex = max($db->listGlobalProblems($practiceSetName)) + 1;
          #WeBWorK::ContentGenerator::RECORD::writeLOG("LOG=TUTOR.FLAG.FOUND.PROBLEMRECORD=addProblemToSet(setName => $practiceSetName, sourceFile => $source, problemID => $newIndex, value => 1, maxAttempts => -1);");

	  my $problemRecord = $self->WeBWorK::ContentGenerator::Instructor::addProblemToSet(setName => $practiceSetName, sourceFile => $source, problemID => $newIndex, value => 1, maxAttempts => -1);
          #WeBWorK::ContentGenerator::RECORD::writeLOG("-----> result is $problemRecord");
	  if ($newIndex > 0) {

	    $a = `php /var/www/html/connecting/workWithWWDB/recordConceptBankFor_courseID_userID_practiceSet_problemID_pgSourcefile.php $conceptBank $courseID $userID $practiceSetName $newIndex $source`;
            #WeBWorK::ContentGenerator::RECORD::writeLOG("\nphp /var/www/html/connecting/workWithWWDB/recordConceptBankFor_courseID_userID_practiceSet_problemID_pgSourcefile.php $conceptBank $courseID $userID $practiceSetName $newIndex $source\n");
            #WeBWorK::ContentGenerator::RECORD::writeLOG("\n---a is $a\n");
	  }
	}

    }
    
    #$self->WeBWorK::ContentGenerator::Instructor::assignSetToUser($userID, $newSetRecord);
    

    #Now, add 'group:$conceptBank' to the final test for the student:


    my $finalSetName = "Final_" . $userID . "_" . $setID;
    #my $finalSetClass = $ce->{dbLayout}->{set_version}->{record};
    my $finalSetRecord = $db->getGlobalSet($finalSetName);
    if (defined($finalSetRecord)) {
	#The set already exists.  We're happy!
    }
    else {
        #create the set:
	$finalSetRecord = $db->{set}->{record}->new();
	$finalSetRecord->set_id($finalSetName);
	$finalSetRecord->set_header("");
	$finalSetRecord->hardcopy_header("");

        #Hard-code the initial time stamp.  Should this come from a database?
	#$finalSetRecord->open_date(1251619388 + 60*60*24*7*2 + 60*60*24); #open on 8/30/2009 + 2 weeks, 1 day (Monday at 1am)
	#$finalSetRecord->due_date(1251619388 + 60*60*24*7*2 + 60*60*24*4); #close on 8/30/2009 + 2 weeks, 4 days (Thursday at 1am)
	#$finalSetRecord->answer_date(1251619388 + 60*60*24*7*3); #due date on 8/30/2009 + 3 weeks

	#Make the quizzes open immediately for demonstrations.
	$finalSetRecord->open_date(time() + 0*60*60*24*7);
	$finalSetRecord->due_date(time() + 1*60*60*24*7);
	$finalSetRecord->answer_date(time()+3*60*60*24*7);




	$finalSetRecord->assignment_type("gateway");
	$finalSetRecord->published(1);
	$finalSetRecord->version_time_limit(60*60);
	$finalSetRecord->time_limit_cap(0);
	$finalSetRecord->attempts_per_version(1);
	$finalSetRecord->time_interval(0);   #time interval for new test versions
	$finalSetRecord->versions_per_interval(1);
	$finalSetRecord->problem_randorder(0);
	$finalSetRecord->problems_per_page(1);
	$finalSetRecord->hide_score("N");
	#$finalSetRecord->hide_score_by_problem("");
	$finalSetRecord->restrict_ip("No");
	$finalSetRecord->relax_restrict_ip("No");
	$finalSetRecord->hide_work("N");

	eval {$db->addGlobalSet($finalSetRecord)};
	if ($@) {
	  #problem creating the set $finalSetRecord
	}
	else {
	  #the set was created!
	}

	#add the two correct banks for this user:
	my $bank1 = "group:" . $setID . "_" . $userID . "_tcerroc1";
	my $bank2 = "group:" . $setID . "_" . $userID . "_tcerroc2";


	my $i;
	for ($i = 1; $i <= 2; $i++) {

	    #Add two source files to the final quiz correct banks
	    my $correctSetName = $setID . "_" . $userID . "_tcerroc" . $i;

	    #my $userSetClass = $ce->{dbLayout}->{set_version}->{record};
	    my $newSetRecord = $db->getGlobalSet($correctSetName);

	    if (defined($newSetRecord)) {
	       #The set already exists.  We're happy!
	    }
	    else {
	      #create the set:
	        $newSetRecord = $db->{set}->{record}->new();
	        $newSetRecord->set_id($correctSetName);
	        $newSetRecord->set_header("");
	        $newSetRecord->hardcopy_header("");


	        $newSetRecord->open_date(time()+0*60*60*24*7);
	        $newSetRecord->due_date(time()+18*60*60*24*7);
	        $newSetRecord->answer_date(time()+25*60*60*24*7);


	        eval {$db->addGlobalSet($newSetRecord)};
	        if ($@) {
	          #problem creating the set $correctSetName
	        }
	        else {
	          #the set was created!
	        }
	    }

	#      my $newIndex = max($db->listGlobalProblems($correctSetName)) + 1;


	}

        my $problemRecord;

        if (max($db->listGlobalProblems($setID . "_" . $userID . "_tcerroc1")) >= 1) {
          $problemRecord = $self->WeBWorK::ContentGenerator::Instructor::addProblemToSet(setName => $finalSetName, sourceFile => $bank1, problemID => 1, value => 1, maxAttempts => 1);
          $problemRecord = $self->WeBWorK::ContentGenerator::Instructor::addProblemToSet(setName => $finalSetName, sourceFile => $bank2, problemID => 2, value => 1, maxAttempts => 1);
        }

	#assign this final test to the user:
	#Done is separate function
        #$self->WeBWorK::ContentGenerator::Instructor::assignSetToUser($userID, $finalSetRecord);
    }

    my $newIndex = max($db->listGlobalProblems($finalSetName)) + 1;
    my $problemRecord = $self->WeBWorK::ContentGenerator::Instructor::addProblemToSet(setName => $finalSetName, sourceFile => "group:$conceptBank", problemID =>$newIndex, value=>1, maxAttempts => 1);

    #assign this final test to the user:
    #Done in separate function
    #$self->WeBWorK::ContentGenerator::Instructor::assignSetToUser($userID, $finalSetRecord);
    return 1;

}

sub assignPracticeAndFinalQuizForUser {
    my ($self, @data) = @_;
    #my $set = $self->{set};
    my $db = $self->{db};
    my $r = $self->r;
    #my $ce = $r->ce;
    my $user = $r->param('user');
    my $urlpath = $r->urlpath;
    my $courseID = $urlpath->arg('courseID');
    my ($userID, $setID) = @data;

    #return 1 if we don't want the system to automatically generate final quizzes and practice sets for users.
    return 1;

    my $practiceSetName = "Practice_" . $userID . "_" . $setID;
    #my $userSetClass = $ce->{dbLayout}->{set_version}->{record};
    my $practiceSetRecord = $db->getGlobalSet($practiceSetName);

    if (defined($practiceSetRecord)) {
      #The set already exists.  We're happy.  Assign this set to the user:
      $self->WeBWorK::ContentGenerator::Instructor::assignSetToUser($userID, $practiceSetRecord);
    }

    my $finalQuizSetName = "Final_" . $userID . "_" . $setID;
    #my $finalQuizSetClass = $ce->{dbLayout}->set_version}->{record};
    my $finalQuizSetRecord = $db->getGlobalSet($finalQuizSetName);
    if (defined($finalQuizSetRecord)) {
      #The final quiz exists.  We're happy.  Assign this final quiz to the user:
      $self->WeBWorK::ContentGenerator::Instructor::assignSetToUser($userID, $finalQuizSetRecord);
    }
} 

  
=head1 CLEARFLAG()
=cut
sub clearFlag {
    
    my ($userID, $courseName, $setID, $problemID, $file) = @_;
    my @flagData = ("$userID", "$courseName", "$setID", "$problemID");
	
	if(WeBWorK::ContentGenerator::RECORD::removeTutorialFlag(@flagData)){
		return 1;		
	}
	return 0;

}


sub getFlaggedSetName{
	
	my @probVersions = WeBWorK::ContentGenerator::RECORD::getFlaggedProblems(@_);
	return @probVersions;

}


sub getFlaggedSet{
	
	my @probVersions = WeBWorK::ContentGenerator::RECORD::getFlaggedProblems(@_);
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
sub hasFlag {
	
    return WeBWorK::ContentGenerator::RECORD::hasTutorialFlag(@_);

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

sub addToSet{
	
	## my ($self, @args) = @_;
	
	
	
	
	## ADD PROBLEMS TO SET NAME 'QuizProblems'
	
    	###  WeBWorK::ContentGenerator::Instructor::addProblemToSet($self, %args);
    	        
        
    ## ADD SET TO USER DATABASE

        
        
	
	return 1;
}


1;
        

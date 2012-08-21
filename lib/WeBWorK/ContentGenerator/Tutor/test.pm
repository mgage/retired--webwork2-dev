
use strict;
use warnings;
use Exporter;
use Tutor;

print "================================================================================================\n";
print " TESTING TUTOR\n";
print "================================================================================================\n";
#######################################################################################################
#### THE FOLLOWING INTERFACES THAT WEBWORK USES TO UTILIZE THE TUTORIAL MODULE.
#######################################################################################################                     
#	TEST1(&USERA);  	#TESTS THE HAS.FLAG()
#	TEST2(&USERA);  	#TESTS THE GET.FLAGGED.VERSIONS() 
#	TEST3(&USERA);  	#TESTS THE GET.TUTORIAL.HTML()
#	TEST4(&USERA);  	#TESTS THE MONITOR()
#	TEST5(&LOGER);		#TESTS THE LOGGER
#######################################################################################################
#######################################################################################################

sub TEST1{
	
	my @data = my ($userID, $answerScore, $problemVersion, $session) = @_;
	#######################################################################################################
	#######################################################################################################
	##  02.  TEST HAS TUTORIALS()
	print "\n01. HASFLAG() FOR: USER ID: $userID\n";
	print "   >Go\n";
	
	
	my $hasFlag = hasFlag($userID);
	
	
	
	print "   >Go.result ($hasFlag)\n";
	#######################################################################################################
	#######################################################################################################	


}
sub TEST2{
	my @data = my ($userID, $answerScore, $problemVersion, $session) = @_;
	#######################################################################################################
	#######################################################################################################
	##  03.  TEST GET.FLAG.VERSION()
	print "\n02. GETFLAGVERSION() FOR: USER ID: $userID\n";
	print "   >Go\n";
	
	my @requestedVersion = getFlaggedVersion($userID);
	my $vSize = @requestedVersion;
	
	print "   <Go.result : $vSize|";
	foreach my $probs (@requestedVersion){
		print "$probs|";
	}
	print "\n";
	#######################################################################################################
	#######################################################################################################
}
sub TEST3{

	my @data = my ($userID, $answerScore, $problemVersion, $session) = @_;
	my $file;
	print "\n03. GETTUTORIALHTML() FOR: PROBLEM VERSION: $problemVersion\n";
	print "   >Go\n";	
	
	
	#######################################################################################################
	#######################################################################################################
	##  GET THE TUTORIAL SET
	my @tutorialSet = getTutorial($userID,$problemVersion);	
	foreach my $set (@tutorialSet){
		$file = ("$set".".tutorial");
	}
	print "   >Go.result: FILE: $file\n";
	print "   >Go\n";
	
	#######################################################################################################
	#######################################################################################################
	##  GET THE HTML LINES
	my @html = getHTML($file);
	print "   >Go.result: (".@html.")";
}
sub TEST4{

	my @data = my ($userID, $answerScore, $problemVersion, $session) = @_;
	#######################################################################################################
	#######################################################################################################
	##  01.  TEST MONITOR()
	print "\n03. MONITOR() FOR: USER ID: $userID  SCORE: $answerScore   PROBLEM VERSION: ";
	print "$problemVersion \n\n";
	print "   >Go\n";
	my $monitorResult = monitor(@data);
	print "   >Go.result = $monitorResult\n";
	#######################################################################################################
	#######################################################################################################
}
sub TEST5{
	my @testData = (	"Problem.initializer() | ",
							"TST 1 | ",
							"Beya : ", 
							"effectiveUser : ",
							"timeNow : ",
							"tmplSet : ",
							"set : ",
							"Problem : ",
							"startProb : ",
							"endProb : ",
							"setName : ",
							"versionNumber \n"   );			
		writeLOG(@testData);
}

sub USERA{
	
	my $userID = "41111";
	my $answerScore = 0;
	my $problemVersion = "A03";
	my $session = 'uiwefakjhfaljskh89asfkjshlasf0890802';
	my @self = ("$userID", "$answerScore", "$problemVersion", "$session");
	
	return @self;	
}
sub LOGER{
	my $user = "Beya";
	my $effectiveUser = "EffectiveBeya";
	my $timeNow = "12:00:09";
	my $tmplSet = "tmplSet";
	my $set = "Set";
	my $Problem = "Problem";
	my $startProb = "01";
	my $endProb = "09";
	my $setName = "Set Name";
	my $versionNumber = "V09";
	my @tutorData = ("$user","$effectiveUser","$timeNow","$tmplSet","$set","$Problem","$startProb","$endProb","$setName","$versionNumber");	
	
	return @tutorData;
}










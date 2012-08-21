package WeBWorK::ContentGenerator::TutorialConsole;
use strict;
use warnings;
use CGI;
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
our $debgTable = '/opt/webwork/webwork2/lib/WeBWorK/ContentGenerator/Tutor/Tables/log.data';
our $testDataW = '/opt/webwork/webwork2/lib/WeBWorK/ContentGenerator/Tutor/Tables/tDebug.data';


my $cgi = new CGI;

      print $cgi->header() . $cgi->start_html(  -title 	=> 'TUTORIAL CONSOLE',
                          						-style 	=> '/~ink/perl_cgi/css/perlcgi.css') .
        					 $cgi->h1('xx') . "\n";
        					 
        		print "<<<<<<". "\n";					 
      my @params = $cgi->param();
        my $FirstName = $cgi->param('FirstName');
        	print $FirstName. "\n";
        my $LastName = $cgi->param('LastName');
        	print $LastName. "\n";
       my $isStudent = $cgi->param('isStudent');
       		print "Are $isStudent ". "\n";
		
	
		print "You are a Student: ". $isStudent;
      
      
      print '<TABLE border="1" cellspacing="0" cellpadding="0">' . "\n";
      

		
		
		


		
      foreach my $parameter (sort @params) {
      	
        say "<tr><th>$parameter</th><td>     " . $cgi->param($parameter) . "     </td></tr>\n";
        
      }
      
      print "</TABLE>\n";
      
      print $cgi->end_html . "\n";
      
      exit (0);

=head1 NAME

WeBWorK::ContentGenerator::GatewayQuiz - display a quiz of problems on one page,
deal with versioning sets

=cut
=head1 WebWork Project
###########################################################################################################################################
###########################################################################################################################################
# WeBWorK Online Homework Delivery System
# Copyright © 2000-2007 The WeBWorK Project, http://openwebwork.sf.net/
# $CVSHeader: webwork2/lib/WeBWorK/ContentGenerator/Problem.pm,v 1.207.2.3.2.1 2008/06/24 16:07:51 gage Exp $
# 
# This program is free software; you can redistribute it and/or modify it under
# the terms of either: (a) the GNU General Public License as published by the
# Free Software Foundation; either version 2, or (at your option) any later
# version, or (b) the "Artistic License" which comes with this package.
# 
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See either the GNU General Public License or the
# Artistic License for more details.
###########################################################################################################################################
###########################################################################################################################################
=cut

package WeBWorK::ContentGenerator::GatewayQuiz;
use base qw(WeBWorK::ContentGenerator);
use strict;
use warnings;
use WeBWorK::CGI;
use File::Path qw(rmtree);
use WeBWorK::Form;
use WeBWorK::PG;
use WeBWorK::PG::ImageGenerator;
use WeBWorK::PG::IO;
use WeBWorK::Utils qw(writeLog writeCourseLog encodeAnswers decodeAnswers
	ref2string makeTempDirectory sortByName before after between 
	formatDateTime);
use WeBWorK::DB::Utils qw(global2user user2global);
use WeBWorK::Debug;
use WeBWorK::ContentGenerator::Instructor qw(assignSetVersionToUser);
use PGrandom;

use WeBWorK::ContentGenerator::RECORD;
use WeBWorK::ContentGenerator::Tutor;


sub templateName { 
	return "gateway";
}

=head1 'CANS'
###########################################################################################################################################
# CGI param interface to this module (up-to-date as of v1.153)
###########################################################################################################################################
#
# Standard params:
# 
#     user - user ID of real user
#     key - session key
#     effectiveUser - user ID of effective user
# 
# Integration with PGProblemEditor:
# 
#     editMode - if set, indicates alternate problem source location.
#                can be "temporaryFile" or "savedFile".
# 
#     sourceFilePath - path to file to be edited
#     problemSeed - force problem seed to value
#     success - success message to display
#     failure - failure message to display
# 
# Rendering options:
# 
#     displayMode - name of display mode to use
#     
#     showOldAnswers - request that last entered answer be shown (if allowed)
#     showCorrectAnswers - request that correct answers be shown (if allowed)
#     showHints - request that hints be shown (if allowed)
#     showSolutions - request that solutions be shown (if allowed)
# 
# Problem interaction:
# 
#     AnSwEr# - answer blanks in problem
#     
#     redisplay - name of the "Redisplay Problem" button
#     submitAnswers - name of "Submit Answers" button
#     checkAnswers - name of the "Check Answers" button
#     previewAnswers - name of the "Preview Answers" button
#
###########################################################################################################################################
# "can" methods
###########################################################################################################################################
# Subroutines to determine if a user "can" perform an action. Each subroutine is
# called with the following arguments:
# 
#     ($self, $User, $EffectiveUser, $Set, $Problem)
# Note that significant parts of the "can" methods are lifted into the 
# GatewayQuiz module.  It isn't direct, however, because of the necessity
# of dealing with versioning there.
###########################################################################################################################################
=cut

sub can_showOldAnswers { 
	
    my ($self, $User, $PermissionLevel, $EffectiveUser, $Set, $Problem, $tmplSet ) = @_;
    my $authz = $self->r->authz;
	
    return(   before( $Set->due_date() )    || 
              $authz->hasPermissions($User->user_id,"view_hidden_work")   ||
              (   $Set->hide_work() eq 'N'  || 
                  (   $Set->hide_work() eq 'BeforeAnswerDate'  && 
                      time > $tmplSet->answer_date                  )        )             );
}

sub can_showCorrectAnswers {
	
    my ($self, $User, $PermissionLevel, $EffectiveUser, $Set, $Problem, $tmplSet, $submitAnswers) = @_;
    my $authz = $self->r->authz;
    my $addOne = defined( $submitAnswers ) ? $submitAnswers : 0;
    my $maxAttempts = $Set->attempts_per_version();
    my $attemptsUsed = $Problem->num_correct + $Problem->num_incorrect + $addOne;
    my $canShowScores = (   $Set->hide_score eq 'N'    ||
                            $Set->hide_score_by_problem eq 'Y' ||
                            (   $Set->hide_score eq 'BeforeAnswerDate'  &&
                                after($tmplSet->answer_date)                )    );
    return ( ( ( after( $Set->answer_date ) || ( $attemptsUsed >= $maxAttempts && $Set->due_date() == $Set->answer_date() ) ) ||
                                                 $authz->hasPermissions($User->user_id, "show_correct_answers_before_answer_date") ) &&
                                               ( $authz->hasPermissions($User->user_id, "view_hidden_work") || $canShowScores )         );
}

sub can_showHints {
		
	return 1;
}

sub can_showSolutions {
	
    my ($self, $User, $PermissionLevel, $EffectiveUser, $Set, $Problem, $tmplSet, $submitAnswers) = @_;
    my $authz = $self->r->authz;
    my $addOne = defined( $submitAnswers ) ? $submitAnswers : 0;
    my $maxAttempts = $Set->attempts_per_version();
    my $attemptsUsed = $Problem->num_correct+$Problem->num_incorrect+$addOne;
    my $canShowScores = ( $Set->hide_score eq 'N' || $Set->hide_score_by_problem eq 'Y' ||(  $Set->hide_score eq 'BeforeAnswerDate' &&
                                                                                             after($tmplSet->answer_date)          ) );
    return ( ( ( after( $Set->answer_date ) || ( $attemptsUsed >= $maxAttempts &&  $Set->due_date() == $Set->answer_date() ) ) ||
                 $authz->hasPermissions($User->user_id, "show_correct_answers_before_answer_date") ) &&
                 (   $authz->hasPermissions($User->user_id, "view_hidden_work") ||
                     $canShowScores ) );
}

sub can_recordAnswers {
	
    my ($self, $User, $PermissionLevel, $EffectiveUser, $Set, $Problem, $tmplSet, $submitAnswers) = @_;
    my $authz = $self->r->authz;
    my $timeNow = ( defined($self->{timeNow}) ) ? $self->{timeNow} : time();
    my $grace = $self->{ce}->{gatewayGracePeriod};
    my $submitTime = ( defined($Set->version_last_attempt_time()) &&  $Set->version_last_attempt_time() ) ? 
                       $Set->version_last_attempt_time() : 
                       $timeNow;
    if ($User->user_id ne $EffectiveUser->user_id) { 
        return $authz->hasPermissions($User->user_id, "record_answers_when_acting_as_student");
    }
    if (before($Set->open_date, $submitTime)) {        
        warn("case 0\n");
        return $authz->hasPermissions($User->user_id, "record_answers_before_open_date");
    } 
    elsif (between($Set->open_date, ($Set->due_date + $grace), $submitTime)) {
        my $addOne = ( defined( $submitAnswers ) && $submitAnswers ) ?  1 : 0;
        my $max_attempts = $Set->attempts_per_version();
        my $attempts_used = $Problem->num_correct+$Problem->num_incorrect+$addOne;
        if ($max_attempts == -1 or $attempts_used < $max_attempts) {
            return $authz->hasPermissions($User->user_id, "record_answers_after_open_date_with_attempts");
        } 
        else {
            return $authz->hasPermissions($User->user_id, "record_answers_after_open_date_without_attempts");
        }
    } 
    elsif (between(($Set->due_date + $grace), $Set->answer_date, $submitTime)) {
        return $authz->hasPermissions($User->user_id, "record_answers_after_due_date");
    } 
    elsif (after($Set->answer_date, $submitTime)) {
        return $authz->hasPermissions($User->user_id, "record_answers_after_answer_date");
    }
}

sub can_checkAnswers {
	
    my ($self, $User, $PermissionLevel, $EffectiveUser, $Set, $Problem, $tmplSet, $submitAnswers) = @_;
    my $authz = $self->r->authz;
    my $timeNow = ( defined($self->{timeNow}) ) ? $self->{timeNow} : time();
    my $grace = $self->{ce}->{gatewayGracePeriod};
    my $submitTime = ( defined($Set->version_last_attempt_time()) &&
                       $Set->version_last_attempt_time() ) ? 
                       $Set->version_last_attempt_time() : 
                       $timeNow;
    my $canShowScores = ( $Set->hide_score eq 'N' || $Set->hide_score_by_problem eq 'Y' ||
                                                     (  $Set->hide_score eq 'BeforeAnswerDate' &&
                                                        after($tmplSet->answer_date)                )          );
    if (before($Set->open_date, $submitTime)) {
        return $authz->hasPermissions($User->user_id, "check_answers_before_open_date");
    } 
    elsif (between($Set->open_date, ($Set->due_date + $grace), $submitTime)) {
        my $addOne = (defined( $submitAnswers ) && $submitAnswers) ?  1 : 0;
        my $max_attempts = $Set->attempts_per_version();
        my $attempts_used = $Problem->num_correct+$Problem->num_incorrect+$addOne;
        
        if ($max_attempts == -1 or $attempts_used < $max_attempts) {
            return ( $authz->hasPermissions($User->user_id, "check_answers_after_open_date_with_attempts") &&
                     (  $authz->hasPermissions($User->user_id, "view_hidden_work") ||
                        $canShowScores                                                  )                         );
        } 
        else {
            return ( $authz->hasPermissions($User->user_id, "check_answers_after_open_date_without_attempts") && 
                     (  $authz->hasPermissions($User->user_id, "view_hidden_work") ||
                        $canShowScores                                                  )                         );
        }
    } 
    elsif (between(($Set->due_date + $grace), $Set->answer_date, $submitTime)) {
        return ( $authz->hasPermissions($User->user_id, "check_answers_after_due_date")  &&
                 (  $authz->hasPermissions($User->user_id, "view_hidden_work") ||
                    $canShowScores                                                 )              );
	} 
    elsif (after($Set->answer_date, $submitTime)) {
        return ( $authz->hasPermissions($User->user_id, "check_answers_after_answer_date") &&
                 ( $authz->hasPermissions($User->user_id, "view_hidden_work") ||
                   $canShowScores ) );
	}
}

sub can_showScore {
	
    my ($self, $User, $PermissionLevel, $EffectiveUser, $Set, $Problem, $tmplSet, $submitAnswers) = @_;
    my $authz = $self->r->authz;
    my $timeNow = ( defined($self->{timeNow}) ) ? $self->{timeNow} : time();
    my $canShowScores = (  $Set->hide_score eq 'N' ||  
                           $Set->hide_score_by_problem eq 'Y' ||
                           (  $Set->hide_score eq 'BeforeAnswerDate' &&
                              after($tmplSet->answer_date)                 )   );

    return ($authz->hasPermissions($User->user_id,"view_hidden_work") ||$canShowScores );
}

=head1 IMPORTED SUBROUTINES - TUTOR
=cut

sub can_session {	
	#########################################################################
	## (ADW): enable a session to be displayed on the screen.
	## only the system.template for session actually uses this call.
	## my ($self, $User, $EffectiveUser, $Set, $Problem) = @_;
	return 1;
}

sub can_showTutorials { 
	
	###########################################################################################
	## If there is a scenarios where tutorial should be disabled, setting should be
	## defined here to control
	## Example:  Is it homework or a Quiz test?
	##
	## For now, subroutine will onlt check flag table if flag exists. If it does, will return 1
	
	return 1;
}

sub session {
	
    #######################################################################################################################################
    ### INITIALIZE VARIABLES
        my ($self)      = @_;
        my $r           = $self->r;
        my $urlpath     = $r->urlpath;
        my $courseID    = 7; #$urlpath->arg("courseID"); #$r->param("section");
        my $sessionPswd = "student"; # password for user in Session.  #$r->param("recitation");
        my $setID       = $self->{set}->set_id if !($self->{invalidSet});
        my $problemID   = $self->{problem}->problem_id if !($self->{invalidProblem});
        my $eUserID     = $r->param("effectiveUser");

    #######################################################################################################################################
    ### BEGIN SESSION INFORMATION
        my $displaySession_start = CGI::start_div({id=>"display-session"});
        my $directions = "webworkTable";
        my $displaySession = <<BLAH;
           <object classid="clsid:d27cdb6e-ae6d-11cf-96b8-444553540000" 
                   codebase="http://download.macromedia.com/pub/shockwave/cabs/flash/swflash.cab#version=9,0,0,0" 
                   width="592.5px" 
                   height="487.5px" 
                   id="session" 
                   align="middle">
                   <param name="allowScriptAccess" value="sameDomain" />
                   <param name="allowFullScreen" value="false" />
                   <param name="movie" value="http://magpie.physics.winona.edu/homework/session.swf?
                                       userName=$eUserID&password=$sessionPswd&courseID=$courseID&courseName=SessionTutorials&
                                       sectionName=&problemSet=$setID&problemNumber=$problemID&directions=$directions" />
                   <param name="quality" value="high" /><param name="bgcolor" value="#ffffff" />	
                   <embed src="http://magpie.physics.winona.edu/homework/session.swf?
                              userName=$eUserID&password=$sessionPswd&courseID=$courseID&courseName=SessionTutorials&
                              sectionName=&problemSet=$setID&problemNumber=$problemID&directions=$directions" 
                              quality="high" bgcolor="#ffffff" width="592.5" height="487.5" name="session" 
                              align="middle" allowScriptAccess="sameDomain" allowFullScreen="false" 
                              type="application/x-shockwave-flash" 
                              pluginspage="http://www.macromedia.com/go/getflashplayer" />
          </object>
BLAH
        my $displaySession_end = CGI::end_div();
    ### END SESSION INFORMATION	
    #######################################################################################################################################
	
	return "$displaySession_start $displaySession $displaySession_end";
}

=head1 'OUTPUT UTILITIES'
###################################################################################################
# output utilities
###################################################################################################
# Note: the substance of attemptResults is lifted into GatewayQuiz.pm,
# with some changes to the output format

# subroutine is modified from that in Problem.pm to produce a different 
#    table format
=cut

sub attemptResults {
	
    my $self = shift;
    my $pg = shift;
    my $showAttemptAnswers = shift;
    my $showCorrectAnswers = shift;
    my $showAttemptResults = $showAttemptAnswers && shift;
    my $showSummary = shift;
    my $showAttemptPreview = shift || 0;
    my $r = $self->{r};
    my $setName = $r->urlpath->arg("setID");
    my $ce = $self->{ce};
    my $root = $ce->{webworkURLs}->{root};
    my $courseName = $ce->{courseName};
    my @links = ("Homework Sets" , "$root/$courseName", "navUp");
    my $tail = "";
    my $problemResult = $pg->{result};
    my @answerNames = @{ $pg->{flags}->{ANSWER_ENTRY_ORDER} };
    my $showMessages = $showAttemptAnswers && grep { $pg->{answers}->{$_}->{ans_message} } @answerNames;
    my $basename = "equation-" . $self->{set}->psvn. "." . $self->{problem}->problem_id . "-preview";
    my %imagesModeOptions = %{$ce->{pg}->{displayModeOptions}->{images}};
    my $imgGen = WeBWorK::PG::ImageGenerator->new(  tempDir         => $ce->{webworkDirs}->{tmp},
                                                    latex           => $ce->{externalPrograms}->{latex},
                                                    dvipng          => $ce->{externalPrograms}->{dvipng},
                                                    useCache        => 1,
                                                    cacheDir        => $ce->{webworkDirs}->{equationCache},
                                                    cacheURL        => $ce->{webworkURLs}->{equationCache},
                                                    cacheDB         => $ce->{webworkFiles}->{equationCacheDB},
                                                    dvipng_align    => $imagesModeOptions{dvipng_align},
                                                    dvipng_depth_db => $imagesModeOptions{dvipng_depth_db},      );
    my %resultsData = ();
       $resultsData{'Entered'}  = CGI::td({-class=>"label"}, "Your answer parses as:");
       $resultsData{'Preview'}  = CGI::td({-class=>"label"}, "Your answer previews as:");
       $resultsData{'Correct'}  = CGI::td({-class=>"label"}, "The correct answer is:");
       $resultsData{'Results'}  = CGI::td({-class=>"label"}, "Result:");
       $resultsData{'Messages'} = CGI::td({-class=>"label"}, "Messages:");  
    my %resultsRows = ();
    foreach ( qw( Entered Preview Correct Results Messages ) ) {
        $resultsRows{$_} = "";
    }
    my $numCorrect = 0;
       
    my $numAns = 0;
    foreach my $name (@answerNames) {
        my $answerResult  = $pg->{answers}->{$name};
        my $studentAnswer = $answerResult->{student_ans}; # original_student_ans
        my $preview       = ( $showAttemptPreview   ?  $self->previewAnswer($answerResult, $imgGen)  : "");
        my $correctAnswer = $answerResult->{correct_ans};
        my $answerScore   = $answerResult->{score};
        my $answerMessage = $showMessages ? $answerResult->{ans_message} : "";            
        my $resultString  = $answerScore == 1 ? "correct" : "incorrect";
        my $pre           = $numAns ? CGI::td("&nbsp;") : "";

        $resultsRows{'Entered'} .= $showAttemptAnswers ?  CGI::Tr( $pre . $resultsData{'Entered'} . 
                                                          CGI::td({-class=>"output"}, $self->nbsp($studentAnswer))) 
                                                       :  "";
        $resultsData{'Entered'}  = '';
        $resultsRows{'Preview'} .= $showAttemptPreview ?  CGI::Tr( $pre . $resultsData{'Preview'} . 
                                                          CGI::td({-class=>"output"}, $self->nbsp($preview)) ) 
                                                       :  "";
        $resultsData{'Preview'}  = '';
        $resultsRows{'Correct'} .= $showCorrectAnswers ?  CGI::Tr( $pre . $resultsData{'Correct'} . 
                                                          CGI::td({-class=>"output"}, $self->nbsp($correctAnswer)) ) 
                                                       : "";
        $resultsData{'Correct'}  = '';
        $resultsRows{'Results'} .= $showAttemptResults ?  CGI::Tr( $pre . $resultsData{'Results'} . 
                                                          CGI::td({-class=>"output"}, $self->nbsp($resultString)) )  
                                                       :  "";
        $resultsData{'Results'}   = '';
        $resultsRows{'Messages'} .=  $showMessages     ?  CGI::Tr( $pre . $resultsData{'Messages'} . 
                                                          CGI::td({-class=>"output"}, $self->nbsp($answerMessage)) ) 
                                                       :  "";
        $numCorrect += $answerScore > 0;
        $numAns++;
    }

    $imgGen->render(refresh => 1);

    my $scorePercent = sprintf("%.0f%%", $problemResult->{score} * 100);
    my $summary = "";
     
    if (scalar @answerNames == 1) {
        if ($numCorrect == scalar @answerNames) {
            $summary .= CGI::div({class=>"gwCorrect"},"This answer is correct.");
        } 
        else {
            $summary .= CGI::div({class=>"gwIncorrect"},"This answer is NOT correct.");
        }
    } 
    else {
        if ($numCorrect == scalar @answerNames) {
            $summary .= CGI::div({class=>"gwCorrect"},"All of these answers are correct.");
        } 
        else {
            $summary .= CGI::div({class=>"gwIncorrect"},"At least one of these answers is NOT correct.");
        }
    }
    
    return  CGI::table(  {-class=>"gwAttemptResults"}, 
                          $resultsRows{'Entered'}, 
                          $resultsRows{'Preview'}, 
                          $resultsRows{'Correct'}, 
                          $resultsRows{'Results'}, 
                          $resultsRows{'Messages'}   ) .
                         ($showSummary ? CGI::p({class=>'attemptResultsSummary'},$summary) : "");
}

sub previewAnswer {
    
    my ($self, $answerResult, $imgGen) = @_;
    my $ce            = $self->r->ce;
    my $EffectiveUser = $self->{effectiveUser};
    my $set           = $self->{set};
    my $problem       = $self->{problem};
    my $displayMode   = $self->{displayMode};
    my $tex           = $answerResult->{preview_latex_string};
	
    return "" unless defined $tex and $tex ne "";
	
    if ($displayMode eq "plainText") {
        return $tex;
    } 
    elsif ($displayMode eq "formattedText") {
        my $tthCommand = $ce->{externalPrograms}->{tth}  . " -L -f5 -r 2> /dev/null <<END_OF_INPUT; echo > /dev/null\n"
                         . "\\(".$tex."\\)\n" . "END_OF_INPUT\n";
        my $result = `$tthCommand`;
        if ($?) {
            return "<b>[tth failed: $? $@]</b>";
        } 
        else {
            return $result;
        }
    } 
    elsif ($displayMode eq "images") {
        $imgGen->add($tex);
    } 
    elsif ($displayMode eq "jsMath") {
        $tex =~ s/</&lt;/g; $tex =~ s/>/&gt;/g;
        return '<SPAN CLASS="math">\\displaystyle{'.$tex.'}</SPAN>';
    }
}

sub pre_header_initialize {	

    ####  1  ####
    #######################################################################################################################################
    ### INITIALIZE VARIABLES	
        my ($self) = @_;
        my $r  = $self->r;
        my $ce = $r->ce;
        my $db = $r->db;
        my $authz = $r->authz;
        my $urlpath = $r->urlpath;
        my $setName = $urlpath->arg("setID");
        my $userName = $r->param('user');
        my $effectiveUserName = $r->param('effectiveUser');
        my $key = $r->param('key');
        my $User = $db->getUser($userName);
           die "record for user $userName (real user) does not exist."   unless defined $User;
        my $EffectiveUser = $db->getUser($effectiveUserName);
           die "record for user $effectiveUserName (effective user) does " . "not exist." unless defined $EffectiveUser;
        my $PermissionLevel   = $db->getPermissionLevel($userName);
           die "permission level record for $userName does not exist (but the " .  "user does? odd...)" unless defined($PermissionLevel);
        my $permissionLevel   = $PermissionLevel->permission;
        my $requestedVersion  = ($setName =~ /,v(\d+)$/) ? $1 : 0;
           $setName =~ s/,v\d+$//;
        my $tmplSet = $db->getMergedSet( $effectiveUserName, $setName );
           $self->{'assignment_type'} = $tmplSet->assignment_type() || 'gateway';
        my @allVersionIds = $db->listSetVersions($effectiveUserName, $setName);
        my $latestVersion = ( @allVersionIds ? $allVersionIds[-1] : 0 );
           $requestedVersion = $latestVersion if ( $requestedVersion !~ /^\d+$/ ||  $requestedVersion > $latestVersion || 
                                                                                    $requestedVersion < 0                     );
           die("No requested version when returning to problem?!")  if ( ( $r->param("previewAnswers") || $r->param("checkAnswers") ||
                                                                           $r->param("submitAnswers"       ) || 
                                                                           $r->param("newPage")  )  &&  ! $requestedVersion );
    ### END - INITIALIZE VARIABLES    
    #######################################################################################################################################
    
    
    ##########            
    ### 2 ####
    #######################################################################################################################################
    ### GET THE NEXT PROBLEM SET
        
        my $set;

        ###################################################################################################################################
        #### IF 'REQUESTED VERSION' OR 'LATEST VERSION', GET SET FROM DB ##################################################################
        if($requestedVersion ) { 
        	$set = $db->getMergedSetVersion($effectiveUserName, $setName, $requestedVersion);
        }
        elsif ($latestVersion ) { 
        	$set = $db->getMergedSetVersion($effectiveUserName, $setName, $latestVersion);
        }
        ###################################################################################################################################
       
        ###################################################################################################################################
        #### ELSE - GENERATE NON-VERSIONED SET FROM GLOBAL2USER
        else {
            my $userSetClass = $ce->{dbLayout}->{set_version}->{record};
               $set = global2user($userSetClass, $db->getGlobalSet($setName));
                      die "set  $setName  not found."  unless $set;
               $set->user_id($effectiveUserName);
               $set->psvn('000');
               $set->set_id("$setName");
               $set->version_id(0);
        }
        my $setVersionNumber = $set->version_id();
        ###################################################################################################################################
		
		#WeBWorK::ContentGenerator::RECORD::writeLOG("LOG=GWQHEAD_2&". "SET.USERID=". $set->user_id($effectiveUserName) . "&" . 
		#                                            "SET.SETID=". $set->set_id("$setName"). "&SET.VERSIONID=". $setVersionNumber. "\n" ); 
		
		   
			
        ###################################################################################################################################
        ### ASSEMBLE SET/VERSION PARAMETERS 
            my $isOpen = $tmplSet->open_date &&  ( after($tmplSet->open_date()) || $authz->hasPermissions($userName, "view_unopened_sets") );
            my $isClosed = $tmplSet->due_date && ( after($tmplSet->due_date())  && 
                                                   ! $authz->hasPermissions( $userName, "record_answers_after_due_date") );
            my @setPNum = $db->listUserProblems($EffectiveUser->user_id, $setName);
               die("Set $setName contains no problems.") if ( ! @setPNum );
            
            my $Problem = $setVersionNumber ? $db->getMergedProblemVersion($EffectiveUser->user_id, $setName, $setVersionNumber, $setPNum[0]) 
                                            : undef;
            my $maxAttemptsPerVersion = $tmplSet->attempts_per_version();
            my $timeInterval          = $tmplSet->time_interval();
            my $versionsPerInterval   = $tmplSet->versions_per_interval();
            my $timeLimit             = $tmplSet->version_time_limit();
               $timeInterval          = 0 if (! defined($timeInterval) || $timeInterval eq '');
               $versionsPerInterval   = 0 if (! defined($versionsPerInterval) || $versionsPerInterval eq '');
            my $currentNumAttempts    = ( defined($Problem) ? $Problem->num_correct() + $Problem->num_incorrect() : 0 );
            my $maxAttempts           = ( defined($Problem) && defined($Problem->max_attempts()) ? $Problem->max_attempts() : -1 );
            my $timeNow               = time();
            my $grace                 = $ce->{gatewayGracePeriod};
            my $currentNumVersions    = 0;   
            my $totalNumVersions      = 0;            
            
            if( $setVersionNumber && ! $self->{invalidSet} ) {
                my @setVersionIDs = $db->listSetVersions($effectiveUserName, $setName);
                my @setVersions   = $db->getSetVersions(map {[$effectiveUserName, $setName,, $_]} @setVersionIDs);
                foreach ( @setVersions ) {
                    $totalNumVersions++;
                    $currentNumVersions++ if( ! $timeInterval || $_->version_creation_time() > ($timeNow - $timeInterval) );
                }
            }
            my $versionIsOpen = 0;
            
            
            
            #my $cnAttempt = 1;
            #WeBWorK::ContentGenerator::RECORD::writeLOG("No=1 PROBLEMR&". "USERID=". $Problem->{user_id} . "&" . "SETID=". $Problem->{set_id}. "&". "SOURCEFILE=". $Problem->{source_file}. "&REQUESTEDVERSION:". $requestedVersion. "\n");
            #WeBWorK::ContentGenerator::RECORD::writeLOG("     SETNAME=". $setName. "&" . "SETVERSIONNUMBER=". $setVersionNumber. "&". "SOURCEFILE=". $Problem->{source_file}. "&REQUESTEDVERSION:". $requestedVersion. "\n");           
            
            
            
            
            
            
            
                                     
            ###################################################################################################################################
            #### IF SESSION IS OPEN & NOT CLOSED & SET IS NOT INVALID
            if ( $isOpen && ! $isClosed && ! $self->{invalidSet} ) {
            	
            	###############################################################################################################################            	
                #### IF REQUESTED VERSION DOES NOT EXIST 
                if( !$requestedVersion ) {  
                    	                     
                    ###########################################################################################################################
                    if ( ( $maxAttempts == -1 || $totalNumVersions < $maxAttempts )       &&
                         ( $setVersionNumber == 0 || ( ( $currentNumAttempts>=$maxAttemptsPerVersion ||
                                                         $timeNow >= $set->due_date + $grace               ) &&
                                                       ( ! $versionsPerInterval || $currentNumVersions < $versionsPerInterval)  )  )  &&
                         ( $effectiveUserName eq $userName || $authz->hasPermissions( $userName, 
                                                                                      "record_answers_when_acting_as_student") )      ) {
                       my $setTmpl = $db->getUserSet($effectiveUserName,$setName);
                          WeBWorK::ContentGenerator::Instructor::assignSetVersionToUser($self, $effectiveUserName, $setTmpl);
                          $setVersionNumber++;
                          $set = $db->getMergedSetVersion($userName, $setName, $setVersionNumber);
                          $Problem = $db->getMergedProblemVersion($userName, $setName, $setVersionNumber, 1);

                          $set->published(1);
                       my $ansOffset = $set->answer_date() - 
                          $set->due_date();
                          $set->version_creation_time( $timeNow );
                          $set->open_date( $timeNow );
                          $set->due_date( $timeNow+$timeLimit ) 
				if (! $set->time_limit_cap || 
				$timeNow+$timeLimit<$set->due_date);
                          $set->answer_date($set->due_date + $ansOffset);
                          $set->version_last_attempt_time( 0 );                      
                          $db->putSetVersion( $set );
                          $versionIsOpen = 1;
                          $currentNumAttempts = 0;
               		 
               		 
               		 #/WeBWorK::ContentGenerator::RECORD::writeLOG("     PROBLEMR&". "USERID=". $Problem->{user_id} . "&" . "SETID=". $Problem->{set_id}. "&". "SOURCEFILE=". $Problem->{source_file}. "&REQUESTEDVERSION:". $requestedVersion. "\n");
         
                
                
                
                    }
                    ########################################################################################################################### 
                    elsif($maxAttempts != -1 && $totalNumVersions > $maxAttempts ) {                  
                        $self->{invalidSet} = "No new versions of " . "this assignment are available,\n" . 
                                              "because you have already taken the " . "maximum number\nallowed." ;                    
                    }
                    ########################################################################################################################### 
                    elsif($effectiveUserName ne $userName && ! $authz->hasPermissions($userName, "record_answers_when_acting_as_student") ) {				
                        $self->{invalidSet} = "User " . "$effectiveUserName is being acted " . "as.  When acting as another user, " .
                                              "new versions of the set cannot be " .
                                              "created.";
                    } 
                    ###########################################################################################################################
                    elsif ($currentNumAttempts < $maxAttemptsPerVersion && $timeNow < $set->due_date() + $grace ) {
                        if( between($set->open_date(), $set->due_date() + $grace, $timeNow) ) {
                            $versionIsOpen = 1;
                        } 
                        else {
                            $versionIsOpen = 0;  
                            $self->{invalidSet} = "No new " .  " versions of this assignment" .  " are available,\nbecause the" .
                                                  " set is not open or its time" .  " limit has expired.\n";
                        }
                    }
                    ########################################################################################################################### 
                    elsif ($versionsPerInterval && ($currentNumVersions >= $versionsPerInterval)){
                        $self->{invalidSet} = "You have already taken" .  " all available versions of this\n" . 
                                              "test in the current time interval.  " .  "You may take the\ntest again after " .
                                              "the time interval has expired.";
                    }
                    ########################################################################################################################### 
                    elsif ( $effectiveUserName ne $userName ) {
                        $self->{invalidSet} = "You are acting as a " . "student, and cannot start new " .
                                              "versions of a set for the student.";
                    }
                    ###########################################################################################################################
                }
                #### END - IF REQUESTED VERSION DOES NOT EXIST
                ###############################################################################################################################
                
                ###############################################################################################################################                
                #### ELSE ... (REQUESTED VERSION DOES EXIST)
                else {
                    ###########################################################################################################################
                    #### IF CURRENT ATTEMP IS LESS THAN MAX ATTEMPT & USERNAME IS E.USERNAME & HAS PERMISSION TO RECORD ANSWER
                    if (( $currentNumAttempts < $maxAttemptsPerVersion )   && 
                        ( $effectiveUserName eq $userName || $authz->hasPermissions($userName, "record_answers_when_acting_as_student")  ) ) {
                        
                        #######################################################################################################################
                        #### IF SET IS WITHIN ALLOWED TIME,
                        if (between($set->open_date(),$set->due_date() + $grace, $timeNow) ) {
                            $versionIsOpen = 1;
                        }
                        #######################################################################################################################
                        #### ELSE (SET IS NOT WITHIN ALLOWED TIME), 
                        else {
                            $versionIsOpen = 0;  # redundant
                        }
                        #######################################################################################################################
                    }
                    ### END - IF CURRENT ATTEMP IS LESS THAN MAX ATTEMPT & USERNAME IS E.USERNAME & HAS PERMISSION TO RECORD ANSWER
                    ###########################################################################################################################
                }
                ###############################################################################################################################                
            }
            #### END - IF SESSION IS OPEN & NOT CLOSED & SET IS NOT INVALID 
            ###################################################################################################################################
            
            ###################################################################################################################################            
            #### ELSE IF SET IS VALID & REQUESTED VERSION DOESN'T EXIST
            elsif ( ! $self->{invalidSet} && ! $requestedVersion ) {
                 $self->{invalidSet} = "This set is closed.  No new set " . "versions may be taken.";
	        }
            #### END - ELSE IF...
            ###################################################################################################################################	             

        ### END - ASSEMBLE SET/VERSION PARAMETERS
        #######################################################################################################################################


        #WeBWorK::ContentGenerator::RECORD::writeLOG("No=2 PROBLEMR&". "USERID=". $Problem->{user_id} . "&" . "SETID=". $Problem->{set_id}. "&". "SOURCEFILE=". $Problem->{source_file}. "&REQUESTEDVERSION:". $requestedVersion. "\n" );      
    
             
        #######################################################################################################################################
        ### SAVE PROBLEM AND USER DATA  
            my $psvn                      = $set->psvn();
               $self->{tmplSet}           = $tmplSet;
               $self->{set}               = $set;
               $self->{problem}           = $Problem;
               $self->{requestedVersion}  = $requestedVersion;
               $self->{userName}          = $userName;
               $self->{effectiveUserName} = $effectiveUserName;
               $self->{user}              = $User;
               $self->{effectiveUser}     = $EffectiveUser;
               $self->{permissionLevel}   = $permissionLevel;
               $self->{isOpen}            = $isOpen;
               $self->{isClosed}          = $isClosed;
               $self->{versionIsOpen}     = $versionIsOpen;
               $self->{timeNow}           = $timeNow;
            my $newPage = $r->param("newPage");
               $self->{newPage} = $newPage;
            my $currentPage = $r->param("currentPage") || 1;
            my $prevOr = $r->param('previewAnswers') || $r->param('previewHack');
               $r->param('previewAnswers', $prevOr) if ( defined( $prevOr ) );
            my $displayMode      = $r->param("displayMode") || $ce->{pg}->{options}->{displayMode};
            my $redisplay        = $r->param("redisplay");
            my $submitAnswers    = $r->param("submitAnswers");
            my $checkAnswers     = $r->param("checkAnswers");
            my $previewAnswers   = $r->param("previewAnswers");
            my $formFields       = { WeBWorK::Form->new_from_paramable($r)->Vars };
               $self->{displayMode}    = $displayMode;
               $self->{redisplay}      = $redisplay;
               $self->{submitAnswers}  = $submitAnswers;
               $self->{checkAnswers}   = $checkAnswers;
               $self->{previewAnswers} = $previewAnswers;
               $self->{formFields}     = $formFields;
           return if $self->{invalidSet} || $self->{invalidProblem};
           return unless $self->{isOpen};
        ### END - SAVE PROBLEM AND USER DATA
        ###################################################################################################################################        	

        ###################################################################################################################################
        ### SET VERSION PERMISSION
            my @args = ( $User, $PermissionLevel, $EffectiveUser, $set, $Problem, $tmplSet);
            my $sAns = ( $submitAnswers ? 1 : 0 );
            my %will;	
            my %want =     ( showOldAnswers        =>  $r->param("showOldAnswers") || $ce->{pg}->{options}->{showOldAnswers},
                             showCorrectAnswers    => ($r->param("showCorrectAnswers") || $ce->{pg}->{options}->{showCorrectAnswers}) &&
                                                      ($submitAnswers || $checkAnswers),
                             showHints             =>  $r->param("showHints") || $ce->{pg}->{options}->{showHints},
                             showSolutions         => ($r->param("showSolutions") || $ce->{pg}->{options}->{showSolutions}) &&
                                                      ($submitAnswers || $checkAnswers),
                             recordAnswers         =>  $submitAnswers,
                             checkAnswers          =>  $checkAnswers,                                                  );
            my %must =     ( showOldAnswers        =>  0,
                             showCorrectAnswers    =>  0,
                             showHints             =>  0,
                             showSolutions         =>  0,
                             recordAnswers         =>  ! $authz->hasPermissions($userName, "avoid_recording_answers"),
                             checkAnswers          =>  0,                                                              );
            my %can =      ( showOldAnswers        =>  $self->can_showOldAnswers(@args), 
                             showCorrectAnswers    =>  $self->can_showCorrectAnswers(@args, $sAns),
                             showHints             =>  $self->can_showHints(@args),
                             showSolutions         =>  $self->can_showSolutions(@args, $sAns),
                             recordAnswers         =>  $self->can_recordAnswers(@args),
                             checkAnswers          =>  $self->can_checkAnswers(@args),
                             recordAnswersNextTime =>  $self->can_recordAnswers(@args, $sAns),
                             checkAnswersNextTime  =>  $self->can_checkAnswers(@args, $sAns),
                             showScore             =>  $self->can_showScore(@args),                         );            
            foreach (keys %must) { $will{$_} = $can{$_} && ($must{$_} || $want{$_}) ;  }            
            $self->{want} = \%want;
            $self->{must} = \%must;
            $self->{can}  = \%can;
            $self->{will} = \%will;
        ### END - SET VERSION PERMISSION
        ###################################################################################################################################       

        ###################################################################################################################################
        ### SET PROBLEM NUMBERS AND MULTIPAGE VARIABLES 
            my @problemNumbers = $db->listProblemVersions($effectiveUserName, $setName,  $setVersionNumber);
            my ( $numPages, $pageNumber, $numProbPerPage ) = ( 1, 0, 0 );
            my ( $startProb, $endProb ) = ( 0, $#problemNumbers );
            
            if( defined($set->problems_per_page) && $set->problems_per_page ) {
                $numProbPerPage = $set->problems_per_page;
                $pageNumber = ($newPage) ? $newPage : $currentPage;
                $numPages = scalar(@problemNumbers)/$numProbPerPage;
                $numPages = int($numPages) + 1 if (int($numPages) != $numPages);
                $startProb = ($pageNumber - 1)*$numProbPerPage;
                $startProb = 0 if ( $startProb < 0 || $startProb > $#problemNumbers );
                $endProb = ($startProb + $numProbPerPage > $#problemNumbers) ?  $#problemNumbers : $startProb + $numProbPerPage - 1;
            }
            
            my @probOrder = (0..$#problemNumbers);           
            
            if( $set->problem_randorder ) {
                my @newOrder = ();
                my $pgrand = PGrandom->new();
                   $pgrand->srand( $set->psvn );
                while ( @probOrder ) { 
                    my $i = int($pgrand->rand(scalar(@probOrder)));
                    push( @newOrder, $probOrder[$i] );
                    splice(@probOrder, $i, 1);
                }
                @probOrder = @newOrder;
            }            
            
            my @probsToDisplay = ();
            
            for( my $i=0; $i<@probOrder; $i++ ) {
                push(@probsToDisplay, $probOrder[$i]) if ( $i >= $startProb && $i <= $endProb );
            }          
            
            my @problems = ();
            my @pg_results = ();
               $self->{errors} = [ ];
            my @mergedProblems = $db->getAllMergedProblemVersions($effectiveUserName, $setName, $setVersionNumber);
            
            foreach my $problemNumber (sort {$a<=>$b } @problemNumbers) {
                my $pIndex = $problemNumber - 1;
                if( ! defined( $mergedProblems[$pIndex] ) ) {
                    $self->{invalidSet} = "One or more of the problems " . "in this set have not been assigned to you.";
                    return;
                }         
                my $ProblemN = $mergedProblems[$pIndex];
                if( not ( $submitAnswers or $previewAnswers or $checkAnswers or $newPage ) and $will{showOldAnswers} ) {
                    my %oldAnswers = decodeAnswers( $ProblemN->last_answer);
                    $formFields->{$_} = $oldAnswers{$_} foreach ( keys %oldAnswers );
                }
                push( @problems, $ProblemN );
                my $pg = $problemNumber;
                if((grep /^$pIndex$/, @probsToDisplay) || $submitAnswers ) {               
                    $pg = $self->getProblemHTML( $self->{effectiveUser}, 
                                                 $setName,
                                                 $setVersionNumber, 
                                                 $formFields, 
                                                 $ProblemN                          );
                }       
                push(@pg_results, $pg);
            }   
        ### END - SET PROBLEM NUMBERS AND MULTIPAGE VARIABLES 
        ###################################################################################################################################        
       
        $self->{ra_problems}   = \@problems;
        $self->{ra_pg_results} = \@pg_results;
        $self->{startProb}     =  $startProb;
        $self->{endProb}       =  $endProb;
        $self->{numPages}      =  $numPages;
        $self->{pageNumber}    =  $pageNumber;
        $self->{ra_probOrder}  = \@probOrder;
}

sub path {
    my ( $self, $args ) = @_;
    my $r = $self->{r};
    my $setName = $r->urlpath->arg("setID");
    my $ce = $self->{ce};
    my $root = $ce->{webworkURLs}->{root};
    my $courseName = $ce->{courseName};
 
    return $self->pathMacro( $args, "Home" => "$root", $courseName => "$root/$courseName",  $setName => "" );
}

sub nav {

    my ($self, $args) = @_;
    my $r = $self->{r};
    my $setName = $r->urlpath->arg("setID");
    my $ce = $self->{ce};
    my $root = $ce->{webworkURLs}->{root};
    my $courseName = $ce->{courseName};
    my @links = ("Problem Sets" , "$root/$courseName", "navUp");
    my $tail = "";
    
    return $self->navMacro($args, $tail, "", @links);
}

sub options { 

    my ($self) = @_;
    
    return if $self->{invalidSet} or $self->{invalidProblem};
    return unless $self->{isOpen};
	
    my $displayMode = $self->{displayMode};
    my %can = %{ $self->{can} };
	
    my @options_to_show = "displayMode";
       push @options_to_show, "showOldAnswers" if $can{showOldAnswers};
       push @options_to_show, "showHints" if $can{showHints};
       push @options_to_show, "showSolutions" if $can{showSolutions};
	
    return $self->optionsMacro( options_to_show => \@options_to_show, );
}

sub body {

    ####  1  ####
    #######################################################################################################################################
    ### INITIALIZE VARIABLES    
        my $self = shift();
        my $r = $self->r;
        my $ce = $r->ce;
        my $db = $r->db;
        my $authz = $r->authz;
        my $urlpath = $r->urlpath;
        my $user = $r->param('user');
        my $effectiveUser = $r->param('effectiveUser');
        my $timeNow = $self->{timeNow};
        my $grace = $ce->{gatewayGracePeriod};
        
        
        ###################################################################################################################################
        ### IF INVALID SET & PROCTORED GATEWAY : DELETE PROCTOR ID AND DISPLAY 'INVALID PROBLEM'        
        if( $self->{invalidSet}) {
            if( $self->{'assignment_type'} eq 'proctored_gateway' ) {
                my $proctorID = $r->param('proctor_user');
                if( $proctorID ) {
                    eval{ $db->deleteKey("$effectiveUser,$proctorID"); };
                    eval{ $db->deleteKey("$effectiveUser,$proctorID,g"); };
                }
            }
            return CGI::div({class=>"ResultsWithError"},  
                            CGI::p("The selected problem (" . $urlpath->arg("setID") . ") is not " . "a valid set for $effectiveUser:"),
                            CGI::p($self->{invalidSet}));
        }
        ### END - IF INVALID SET OR PROCTORED GATEWAY
        ###################################################################################################################################        
        
        
        my $tmplSet = $self->{tmplSet};
        my $set = $self->{set};
        my $Problem = $self->{problem};
        my $permissionLevel = $self->{permissionLevel};
        my $submitAnswers = $self->{submitAnswers};
        my $checkAnswers = $self->{checkAnswers};
        my $previewAnswers = $self->{previewAnswers};
        my $newPage = $self->{newPage};
        my %want = %{ $self->{want} };
        my %can = %{ $self->{can} };
        my %must = %{ $self->{must} };
        my %will = %{ $self->{will} };
        my @problems = @{ $self->{ra_problems} };
        my @pg_results = @{ $self->{ra_pg_results} };
        my @pg_errors = @{ $self->{errors} };
        my $requestedVersion = $self->{requestedVersion};
        my $startProb = $self->{startProb};
        my $endProb = $self->{endProb};
        my $numPages = $self->{numPages};
        my $pageNumber = $self->{pageNumber};
        my @probOrder = @{$self->{ra_probOrder}};
        my $setName  = $set->set_id;
        my $versionNumber = $set->version_id;
        my $setVName = "$setName,v$versionNumber";
        my $numProbPerPage = $set->problems_per_page;
        
        
        ###################################################################################################################################
        ### IF PROBLEM HAS ERROR : SET ERROR MESSAGE AND RETURN CG ERROROUTPUT 
        if( @pg_errors ) {
            my $errorNum = 1;
            my ( $message, $context ) = ( '', '' );
            foreach ( @pg_errors ) {
                $message .= "$errorNum. " if ( @pg_errors > 1 );
                $message .= $_->{message} . CGI::br() . "\n";
                $context .= CGI::p((@pg_errors > 1? "$errorNum.": '') . $_->{context} ) . "\n\n" . CGI::hr() . "\n\n";
            }
            return $self->errorOutput( $message, $context );
        }
        ### END - IF PROBLEM HAS ERROR
        ###################################################################################################################################        


    ### END - INITIALIZE VARIABLES
    #######################################################################################################################################



    ####  2  ####
    #######################################################################################################################################
    ### PROCESS EACH PROBLEM QUESTIONS 	
        debug("begin answer processing"); 
       
        my @scoreRecordedMessage = ('') x scalar(@problems);
        
        ###################################################################################################################################
        ### IF 'SUBMIT ANSWER' OR 'PREVIEW/NEWPAGE' & 'RECORD ANSWER' ...
        if ( $submitAnswers || ( ($previewAnswers || $newPage) &&  $can{recordAnswers} ) ) {
            
            
            ###############################################################################################################################
            ### IF 'SUBMIT ANSWER' & 'PROCTORED GATEWAY' : DELETE PROCTOR ID
            if( $submitAnswers &&  $self->{'assignment_type'} eq 'proctored_gateway' ) {
                my $proctorID = $r->param('proctor_user');
                if( $set->attempts_per_version - 1 -  $Problem->num_correct - $Problem->num_incorrect  <= 0 ) {	
                    eval{ $db->deleteAllProctorKeys( $effectiveUser ); };
                } 
                else {
                    eval{ $db->deleteKey("$effectiveUser,$proctorID,g"); };
                        if( $r->param("past_proctor_user") &&  $r->param("past_proctor_key") ) {
                            $r->param("proctor_user", $r->param("past_proctor_user"));
                            $r->param("proctor_key", $r->param("past_proctor_key"));
                        }
                }
                if( $@ ) {
                    die("ERROR RESETTING PROCTOR GRADING KEY(S): $@\n");
                }
            }
            ### END - IF 'SUBMIT ANSWER' & 'PROCTORED GATEWAY'
            ###############################################################################################################################
            
            my @pureProblems = $db->getAllProblemVersions($effectiveUser, $setName, $versionNumber);
                        
            ###############################################################################################################################
            ### FOREACH QUESTION IN A PROBLEM : GET ANSWER, ENCODE ANSWER, SET IT'S PROPERTIES AND PUT IT TO DB ###########################
            
            
            foreach my $i ( 0 .. $#problems ) {
                my $pureProblem = $pureProblems[$i];
                my %answersToStore;
                my %answerHash = ();
                my @answer_order = ();
                
                
                #### GET ANSWERS ##########################################################################################################
                #### IF PG_RESULTS : GET ANSWERS FROM PG_RESULTS
                if( ref( $pg_results[$i] ) ) {
                       %answerHash = %{$pg_results[$i]->{answers}};
                       $answersToStore{$_} = $self->{formFields}->{$_} foreach (keys %answerHash);
                    my @extra_answer_names =  @{ $pg_results[$i]->{flags}->{KEPT_EXTRA_ANSWERS} };
                       $answersToStore{$_} = $self->{formFields}->{$_} foreach (@extra_answer_names);
                       @answer_order = ( @{$pg_results[$i]->{flags}->{ANSWER_ENTRY_ORDER}}, @extra_answer_names );
                } 
                
                #### ELSE - GET ANSWERS FROM FORMFIELDS  ################################################################################## 
                else {
                   my $prefix = sprintf('Q%04d_',$i+1);
                   my @fields = sort grep {/^$prefix/} (keys %{$self->{formFields}});
                      %answersToStore = map {$_ => $self->{formFields}->{$_}} @fields;
                      @answer_order = @fields;
                }                
                
                
                #### ENCODE ANSWERS #######################################################################################################
                my $answerString = encodeAnswers( %answersToStore, @answer_order );
                   $problems[$i]->last_answer( $answerString );
                   $pureProblem->last_answer( $answerString );
                
                
                ###########################################################################################################################
                #### IF 'SUBMIT ANSWERS' AND 'CAN RECORD ANSWER' : PUT ANSWERS TO DB AND WRITE TO LOG 
                if( $submitAnswers && $will{recordAnswers} ) {
                   
                    $problems[$i]->status($pg_results[$i]->{state}->{recorded_score});
                    $problems[$i]->attempted(1);
                    $problems[$i]->num_correct($pg_results[$i]->{state}->{num_of_correct_ans});
                    $problems[$i]->num_incorrect($pg_results[$i]->{state}->{num_of_incorrect_ans});
                    $pureProblem->status($pg_results[$i]->{state}->{recorded_score});
                    $pureProblem->attempted(1);
                    $pureProblem->num_correct($pg_results[$i]->{state}->{num_of_correct_ans});
                    $pureProblem->num_incorrect($pg_results[$i]->{state}->{num_of_incorrect_ans});
                    
                    
                    ### IF 'PUT TO DB' :  DISPLAY RESULT ##################################################################################
                    if( $db->putProblemVersion( $pureProblem ) ) {
                        $scoreRecordedMessage[$i] = "Your " . "score on this problem was " . "recorded.";
                    } 
                    else {
                        $scoreRecordedMessage[$i] = "Your " . "score was not recorded " . "because there was a failure " .
                                                    "in storing the problem " . "record to the database.";
                    }
                    
                    
                    ### WRITE DATA TO LOG #################################################################################################
                    writeLog( $self->{ce}, "transaction",
                              $problems[$i]->problem_id . "\t" .      #5
                              $problems[$i]->set_id . "\t" .          #Trig_transform__graph_amp_midline
                              $problems[$i]->user_id . "\t" .         #badamu07
                              $problems[$i]->source_file . "\t" .     #Library/ASU-topics/setTrigGraphs/c5s3p41_44/c5s3p41_44.pg
                              $problems[$i]->value . "\t" .           #1
                              $problems[$i]->max_attempts . "\t" .    #-1
                              $problems[$i]->problem_seed . "\t" .    #3821
                              $problems[$i]->status . "\t" .          #0
                              $problems[$i]->attempted . "\t" .       #1
                              $problems[$i]->last_answer . "\t" .     #base64_encoded:QW5Td0VyMSMjYSMjQW5Td0VyMiMjYSMjQW5Td0VyMyMjYSMjQW5Td0VyNCMjYQ
                              $problems[$i]->num_correct . "\t" .     #0
                              $problems[$i]->num_incorrect      );    #2
                    #######################################################################################################################          
                                                                           
                }
                #### END - IF 'SUBMIT ANSWERS' AND 'CAN RECORD ANSWER'
                ###########################################################################################################################
                
                
                ###########################################################################################################################
                #### ELSE - IF ONLY 'SUBMIT ANSWERS' : SET 'SCORE RECORDED MESSAGE', 'ELAPSED' AND 'ALLOWED'  
                elsif ( $submitAnswers ) {
                    
                    if( $self->{isClosed}) {
                        $scoreRecordedMessage[$i] = "Your " . "score was not recorded " . "because this problem set " .
                                                    "version is not open.";
                    } 
                    elsif( $problems[$i]->num_correct +  $problems[$i]->num_incorrect >= $set->attempts_per_version ) {
                        $scoreRecordedMessage[$i] = "Your " . "score was not recorded " . "because you have no " .
                                                    "attempts remaining on this " . "set version.";
                    } 
                    elsif( ! $self->{versionIsOpen} ) {
                        my $endTime = ( $set->version_last_attempt_time ) ? $set->version_last_attempt_time : $timeNow;
                        if( $endTime > $set->due_date && $endTime < $set->due_date + $grace){
                            $endTime = $set->due_date;
                        }
                        my $elapsed = int(($endTime - $set->open_date)/0.6 + 0.5)/100;
                        my $allowed = ($set->due_date - $set->open_date)/60;
                           $scoreRecordedMessage[$i] = "Your " . "score was not recorded " . "because you have exceeded " .
                                                       "the time limit for " . "test. (Time taken: $elapsed " . 
                                                       "min; allowed: $allowed min.)";
                    }
                    else {
                        $scoreRecordedMessage[$i] = "Your " . "score was not recorded.";
                    }
                }
                #### END - ELSE IF ONLY 'SUBMIT ANSWERS'
                ###########################################################################################################################


                ###########################################################################################################################                
                #### ELSE PUT QUESTION TO DB                 
                else {
                    $db->putProblemVersion( $pureProblem );
                }
                #### END - ELSE PUT QUESTION TO DB ########################################################################################
                ########################################################################################################################### 
                                   
                                   
            } 
            ### END - FOREACH QUESTION IN A PROBLEM #######################################################################################            
            ###############################################################################################################################
             
                            
            my $answer_log = $self->{ce}->{courseFiles}->{logs}->{'answer_log'};
                                  
            
            ###############################################################################################################################
            ### IF ANSWER LOG IS DEFINED
            if( defined( $answer_log ) ) {
                
                
                ### FOREACH PROBLEM : GET 'ANSWERSTRING', 'SCORES', 'TUTOR.MONITOR' AND SET BUTTON PREFIXES ################################################
                foreach my $i ( 0 .. $#problems ) {
                   
                    my $answerString = '';
                    my $scores = '';
                    
                    #### IF PG_ RESULT : GET 'ANSWERSTRING' AND 'SCORE' ###################################################################
                    if( ref( $pg_results[$probOrder[$i]] ) ) {
                        my %answerHash = %{ $pg_results[$probOrder[$i]]->{answers} };
                        foreach ( sortByName(undef, keys %answerHash) ) {
                            my $sAns = $answerHash{$_}->{original_student_ans} || '';
                               $answerString .= $sAns . "\t";
                               $scores .= $answerHash{$_}->{score}>=1  ?  "1"  :  "0"  if ( $submitAnswers );
                        }
                    } 
                    #### ELSE - GET IT FROM 'FORMSFIELDS' #################################################################################
                    else {
                        my $prefix = sprintf('Q%04d_', ($probOrder[$i]+1));
                        my @fields = sort grep {/^$prefix/} (keys %{$self->{formFields}});
                        foreach ( @fields ) {
                           $answerString .= $self->{formFields}->{$_} . "\t";
                           $scores .= $self->{formFields}->{"probstatus".($probOrder[$i]+1)} >= 1 ?  "1" : "0" if ( $submitAnswers );

                        }
                    }
                    #### END - GET 'ANSWERSTRING' AND 'SCORE' #############################################################################
                    
                    
                    my $answerPrefix;                    
                       $answerString =~ s/\t+$/\t/;
                    
                    
                    #### SET BUTTONS PREFIX ###############################################################################################
                    if( $submitAnswers ) { $answerPrefix = "[submit] "; } 
                        elsif ( $previewAnswers ) { $answerPrefix = "[preview] "; } 
                        else {  $answerPrefix = "[newPage] ";  }
                    if( !$answerString ||  $answerString =~ /^\t$/ ) { $answerString = "$answerPrefix" . "No answer entered\t"; } 
                        else { $answerString = "$answerPrefix" . "$answerString";  }
                    

                    ##(ADW): Record the transaction to the log file for the course.  Include time.  
                    ##(ADW):  FIX THIS:  Only record for the changed pages, or if $answerPrefix == "submit";
                    ##Time format:  (epoc time at action - timestamp)
                    ##           :  (elapsed time since last action -- seconds that a page was viewed (not cumulative))
                    ##           :  (elapsed time for quiz -- cumulative time spent on quiz)
                    ##           :  (total allowed amount of time for quiz)
                    my $adwCurrentPage = $r->param("currentPage") || 1;
                    if (($answerPrefix eq "[submit] ") || ($adwCurrentPage == $i + 1)) {
                      my $adwEndTime = ( $set->version_last_attempt_time ) ? $set->version_last_attempt_time : $timeNow;
                      my $adwElapsedTotal = $adwEndTime - $set->open_date;
                      my $adwPrevTime = $r->param("serverTime");
                      my $adwElapsedPart = $adwEndTime - $adwPrevTime;
                      my $adwAllowed = ($set ->due_date - $set->open_date);
                      writeCourseLog( $self->{ce}, "answer_log",
                                      join("", '|', 
                                           $problems[$i]->user_id,
                                           '|', $setName,
                                           '|', ($i+1), '|', $scores,
                                           "\t$timeNow $adwElapsedPart $adwElapsedTotal / $adwAllowed \t",
                                           "$answerString"),
                                    );
                    }

                    
                    ##########################################################################################################
                    #### TUTOR -  LOG AND MONITOR :  IF STUDENT SCORES < 1, PROBLEM WILL BE ADDED TO 'QUIZPROBLEM'S SET
                    ##########################################################################################################
                    ####
                   
                    #WeBWorK::ContentGenerator::RECORD::writeLOG("\n\n\n\n\nLOG=GWQBODY&".
                    #                                            "USERID=". $problems[$i]->user_id . "&" .
                    #                                            "PROBLEMID=". $problems[$i]->problem_id . "&" .
                    #                                            "SETID=". $problems[$i]->set_id . "&" .
                    #                                            "SCORE=". $scores. "\n"                             ) if $submitAnswers;
                    if ($submitAnswers) {
                      my @monitorData = ($problems[$i]->user_id, $scores, $problems[$i]->set_id, $problems[$i]->problem_id, $problems[$i]->source_file);             
                      $self->WeBWorK::ContentGenerator::Tutor::monitor(@monitorData);
		    }
#(ADW HERE!)
                    #######################################################################################################################            
               
                }
                ### END - FOREACH PROBLEM #################################################################################################              
                my @monitorData = ($problems[0]->user_id, $problems[0]->set_id);
                $self->WeBWorK::ContentGenerator::Tutor::assignPracticeAndFinalQuizForUser(@monitorData);
            }
            ### END - IF ANSWER LOG IS DEFINED 
            ###############################################################################################################################
        
        }
        ### END - IF 'SUBMIT ANSWER' OR 'PREVIEW/NEWPAGE' & 'RECORD ANSWER'
        ###################################################################################################################################


        ###################################################################################################################################
        if(( $submitAnswers && ( $will{recordAnswers} || ( ! $set->version_last_attempt_time() && $timeNow > $set->due_date + $grace )))||
	       ( ! $can{recordAnswersNextTime} && $set->assignment_type() eq 'proctored_gateway' ) ) {
        
            my $setName = $set->set_id();
            if( $submitAnswers &&($will{recordAnswers} || ( ! $set->version_last_attempt_time() && $timeNow > $set->due_date + $grace))){
                $set->version_last_attempt_time( $timeNow );
            }
            if ( ! $can{recordAnswersNextTime} && $set->assignment_type() eq 'proctored_gateway' ) {
                $set->assignment_type( 'gateway' );
            }
            $db->putSetVersion( $set );
        }
        ###################################################################################################################################

        debug("end answer processing");
   
   
    ### END - PROCESS EACH PROBLEM QUESTIONS        
    #######################################################################################################################################



    ####  3  ####
    #######################################################################################################################################
    #######################################################################################################################################
    ### DISPLAY SETTINGS	
    
        my $canShowProblemScores =   $can{showScore} && 
                                   ( $set->hide_score eq 'N' || $set->hide_score_by_problem eq 'N' || 
                                     $authz->hasPermissions($user, "view_hidden_work"));
        my $canShowWork = $authz->hasPermissions( $user, "view_hidden_work") || 
                                                  ( $set->hide_work eq 'N' || 
                                                    ( $set->hide_work eq 'BeforeAnswerDate' && $timeNow>$tmplSet->answer_date));
        my @probStatus = ();
        my $recordedScore = 0;
        my $totPossible = 0;
        foreach ( @problems ) {
            $totPossible += $_->value();
            #(ADW):  Make recordedScore contain only full credit for quizzes:
            #$recordedScore += $_->status*$_->value() if (defined($_->status));
            if (defined($_->status)) {
              $recordedScore += $_->status*$_->value() == 1 ? 1 : 0;
            }
            push( @probStatus, ($r->param("probstatus" . $_->problem_id) || $_->status || 0) );
        }
        my $attemptScore = 0;
	#(ADW)Report whole score, not partial score:
        #Every attemptScore will be switched to wholeAttemptScore below
	#This works in conjunction with recordScore, which was modified to be a whole score as well.
	my $wholeAttemptScore = 0;


        ###################################################################################################################################        
        ### IF 'SUBMITANSWER' OR 'CHECKANSWER' : GET PVALUE, PSCORE, NUMPARTS AND SET 'PROBLEMSTATUS' AND 'ATTEMPSCORE'
        if( $submitAnswers || $checkAnswers ) {
            
            my $i=0;
            
            
            ###############################################################################################################################
            ### FOREACH PG_RESULTS : GET 'PVALUE', 'PSCORE', 'NUMPARTS' 
            foreach my $pg ( @pg_results ) {
                
                my $pValue = $problems[$i]->value();
                my $pScore = 0;
                my $numParts = 0;
                if( ref( $pg ) ) {
                    foreach (@{$pg->{flags}->{ANSWER_ENTRY_ORDER}}){
                        $pScore += $pg->{answers}->{$_}->{score};
                        $numParts++;
                    }
                    $probStatus[$i] = $pScore/($numParts>0 ? $numParts : 1);
                } 
                else {
                    $pScore = $probStatus[$i];
                }
                $attemptScore += $pScore*$pValue/($numParts > 0 ? $numParts : 1);

                #(ADW)Report only whole score, not partial score:
		my $partScore = $pScore*$pValue/($numParts > 0 ? $numParts : 1);
		$wholeAttemptScore += $partScore == 1 ? 1 : 0;

                $i++;
            }
            ### END - FOREACH PG_RESULTS 
            ###############################################################################################################################
        
        }
        ### END - IF 'SUBMITANSWER' OR 'CHECKANSWER' 
        ###################################################################################################################################        
       
       
        ###################################################################################################################################
        ### SET TIME, ELLAPSED TIME AND ATTEMPTS 
        my $allowed = ($set->due_date - $set->open_date)/60;
        my $exceededAllowedTime = 0;
        my $endTime = ( $set->version_last_attempt_time ) ? $set->version_last_attempt_time : $timeNow;
        if( $endTime > $set->due_date && $endTime < $set->due_date + $grace ) {
            $endTime = $set->due_date;
        } 
        elsif( $endTime > $set->due_date ) {
            $exceededAllowedTime = 1;
        }
        my $elapsedTime = int(($endTime - $set->open_date)/0.6 + 0.5)/100;
        my $numLeft = $set->attempts_per_version - $Problem->num_correct - $Problem->num_incorrect - ( $submitAnswers && 
                                                                                                       $will{recordAnswers}  ?    
                                                                                                       1  :  0 );
        my $attemptNumber = $Problem->num_correct + $Problem->num_incorrect;
        my $testNoun = ($set->attempts_per_version > 1) ? "submission" : "test";
        my $testNounNum = ( $set->attempts_per_version > 1 ) ?  "submission (test " : "test (";
        ### END - SET TIME, ELLAPSED TIME AND ATTEMPTS
        ###################################################################################################################################        

           
    ####  4  ####
    #######################################################################################################################################
    #######################################################################################################################################
    ### PRINT / DISPLAY         
                               
        ###################################################################################################################################
        ### IF 'SUBMIT ANSWERS' : PRINT 'SCORE' AND 'RECMSG'
        if( $submitAnswers ) {
            
            my $divClass = 'ResultsWithoutError';
            my $recdMsg = '';
            
            foreach ( @scoreRecordedMessage ) {
                if( $_ ne 'Your score on this problem was recorded.') {
                    $recdMsg = $_;
                    $divClass = 'ResultsWithError';
                    last;
                }
            }
            print CGI::start_div({class=>$divClass});
            if( $recdMsg ) {
                print CGI::strong("Your score on this $testNounNum ", "$versionNumber) was NOT recorded.  ", $recdMsg), CGI::br();
            } 
            else {
                print CGI::strong("Your score on this $testNounNum ", "$versionNumber) WAS recorded."), CGI::br();
                if( $can{showScore} ) {
                    #(ADW): Change to report whole score, not partial score:
                    print CGI::strong("Your score on this " . "$testNoun is ", "$wholeAttemptScore/$totPossible.");
                } 
                else {
                    my $when = ($set->hide_score eq 'BeforeAnswerDate')  ? ' until ' . formatDateTime($set->answer_date)  : '';
                    print CGI::br() . "(Your score on this $testNoun " . "is not available$when.)";
                }
            }
            print CGI::end_div();
	    #(ADW):Changed $attemptScore to $wholeAttemptScore, to report whole score:
            if( $set->attempts_per_version > 1 && $attemptNumber > 1 && $recordedScore != $wholeAttemptScore && $can{showScore} ) {
                print CGI::start_div({class=>'gwMessage'});
                print "The recorded score for this test is ", "$recordedScore/$totPossible.";
                print CGI::end_div();
            }
        }
        ### END - IF 'SUBMIT ANSWERS' 
        ###################################################################################################################################


        ###################################################################################################################################        
        ### ELSE IF 'CHECK ANSWERS' & 'CAN SHOW SCORE' : PRINT 'RECORDED ANSWER'
        elsif ( $checkAnswers ) {
            if( $can{showScore} ) {
                print CGI::start_div({class=>'gwMessage'});
		#(ADW):Changed $attemptScore to $wholeAttemptScore, to report whole score:
                print CGI::strong("Your score on this (checked, not ", "recorded) submission is ", "$wholeAttemptScore/$totPossible."), 
				      CGI::br();
                print "The recorded score for this test is " . "$recordedScore/$totPossible.  ";
                print CGI::end_div();
            }
        }
        ### END - ELSE IF 'CHECK ANSWERS'        
        ###################################################################################################################################


        ###################################################################################################################################                
        ### IF 'RECORD ANSWERS NEXT TIME' : PROCESS AND PRINT 'TIMELEFT', 'ATTEMPTS' AND 'PROBSTATUS'
        if( $can{recordAnswersNextTime} ) {
            
            my $timeLeft = $set->due_date() - $timeNow;
                print CGI::div({-id=>"gwTimer"},"\n");
                print CGI::startform({-name=>"gwTimeData", -method=>"POST", -action=>$r->uri});
                print CGI::hidden({-name=>"serverTime", -value=>$timeNow}),  "\n";
                print CGI::hidden({-name=>"serverDueTime",  -value=>$set->due_date()}), "\n";
                print CGI::endform();
                
                if( $timeLeft < 1 && $timeLeft > 0 ) {
                    print CGI::span({-class=>"resultsWithError"}, CGI::b("You have less than 1 minute ", "to complete this test.\n"));
                } 
                elsif ( $timeLeft <= 0 ) { 
                    print CGI::span({-class=>"resultsWithError"}, CGI::b("You are out of time.  ",  "Press grade now!\n"));
                }              
                if( $set->attempts_per_version > 1 ) {
                    print CGI::em("You have $numLeft attempt(s) remaining ", "on this test.");
                    if( $numLeft < $set->attempts_per_version && $numPages > 1 && $can{showScore} ) {
                        print CGI::start_div({-id=>"gwScoreSummary"}), CGI::strong({},"Score summary for " . "last submit:");
                        print CGI::start_table({"border"=>0, "cellpadding"=>0, "cellspacing"=>0});
                        print CGI::Tr({},CGI::th({-align=>"left"}, ["Prob","","Status","", "Result"]));
                        for( my $i=0; $i<@probStatus; $i++ ) {
                            print CGI::Tr({}, CGI::td({},[($i+1),"",int(100*$probStatus[$probOrder[$i]]+0.5) . "%","", 
                            $probStatus[$probOrder[$i]] == 1 ? "Correct" : "Incorrect"]));
                        }
                        print CGI::end_table(), CGI::end_div();
                    }
                }
        }
        ### END - IF NEEDS NEEDS TO RECORD ANSWER, PROCESS AND DISPLAY TIME LEFT ##########################################################         
        ###################################################################################################################################



        ###################################################################################################################################
        ### ELSE - (IF ANSWERS DON'T NEED TO BE RECORDED)
        else {
        	
            print CGI::start_div({class=>'gwMessage'});


            ###############################################################################################################################
            ### IF NOT 'CHECK ANSWER' AND NOT 'SUBMIT ANSWERS' : PRINT SCMSG
            if( ! $checkAnswers && ! $submitAnswers ) {
               if( $can{showScore} ) {
		    #(ADW)Make this report the whole score, not the partial score.
                    my $scMsg = "Your recorded score on this " . "(test number $versionNumber) is " . "$recordedScore/$totPossible";
                    if( $exceededAllowedTime &&  $recordedScore == 0 ) {
                        $scMsg .= ", because you exceeded " . "the allowed time.";
                    } 
                     else {
                        $scMsg .= ".  ";
                    }
                    print CGI::strong($scMsg), CGI::br();
			    }
		    }
            ### END - IF NOT 'CHECK ANSWER' AND NOT 'SUBMIT ANSWERS'
            ###############################################################################################################################		    		
				
				
            ###############################################################################################################################
            ### IF LAST ATTEMPT VERSION : PRINT 'ELAPSED TIME'            
            if( $set->version_last_attempt_time ) {
                print "Time taken on test: $elapsedTime min " . "($allowed min allowed).";
            } 
            elsif ( $exceededAllowedTime && $recordedScore != 0 ) {
                print "(This test is overtime because it was not " . "submitted in the allowed time.)";
            }
            ### END - IF LAST ATTEMPT VERSION
            ###############################################################################################################################


            print CGI::end_div();
            

            ###############################################################################################################################                
            ### IF CAN SHOW WORK, PRINT LINK
            if( $canShowWork ) {
                my $link = $ce->{webworkURLs}->{root} . '/' . $ce->{courseName} . '/hardcopy/' . $set->set_id . ',v' . 
                           $set->version_id . '/?' .  $self->url_authen_args;
                   print "The test (which is number $versionNumber) may " . "no longer be submitted for a grade";
                   print "" . (($can{showScore}) ? ", but you may still " . "check your answers." : ".") ;
                my $printmsg = CGI::div({-class=>'gwPrintMe'}, CGI::a({-href=>$link}, "Print Test"));
                   print $printmsg;
            }
            ### END - IF CAN SHOW WORK
            ###############################################################################################################################
            
        }                
        ### END - ELSE IF NO NEED TO RECORD ANSWERS, DISPLAY REASONS
        ###################################################################################################################################        	
	

        ###################################################################################################################################
        ### URI HACK PREVENTION        
        
        my $action = $r->uri();
           $action =~ s/proctored_quiz_mode/quiz_mode/ 
        
        ###################################################################################################################################           
        
        
        
        ###################################################################################################################################
        ### IF SET IS 'GATEWAY' : SET FORM ACTION, 
        if( $set->assignment_type() eq 'gateway' );
            
            my $setname = $set->set_id;
            my $setvnum = $set->version_id;
               $action =~ s/(quiz_mode\/$setname)\/?$/$1,v$setvnum\//;  #"


			### IF NOT 'RECORD ANSWER NEXT TIME' AND 'CAN NOT SHOW WORK' : PRINT RESULT NOT AVAILABLE  
            if( ! $can{recordAnswersNextTime} && ! $canShowWork ) {
                my $when = ( $set->hide_work eq 'BeforeAnswerDate' ) ? ' until ' . formatDateTime($set->answer_date) : '';
                   print CGI::start_div({class=>"gwProblem"});
                   print CGI::strong("Completed results for this assignment are " . "not available$when.");
                   print CGI::end_div();
            }
            
            ### ELSE :  PRINT FORMS
            else {
            	
            	###########################################################################################################################
            	### PRINT FORM PROPERTIES 
                print CGI::startform({-name=>"gwquiz", -method=>"POST", -action=>$action}), $self->hidden_authen_fields, 
                                                                                            $self->hidden_proctor_authen_fields;
                print CGI::hidden({-name=>'previewHack', -value=>''}), CGI::br();
                ##(ADW) Add serverTime so we can calculate amount of time spent on each question
                ##(ADW) when there is one question per page.
                print CGI::hidden({-name=>'serverTime', -value=>$timeNow}), "\n";
                ###########################################################################################################################

                ###########################################################################################################################
                ### PRINT PAGE NUMBERS 
                if ( $numProbPerPage && $numPages > 1 ) { 
                    print CGI::hidden({-name=>'newPage', -value=>''});
                    print CGI::hidden({-name=>'currentPage', -value=>$pageNumber});
                }
                ###########################################################################################################################
                

                ###########################################################################################################################                
                ### PRINT JAVA JUMP LINKS 
                my $jsprevlink = 'javascript:document.gwquiz.previewHack.value="1";';
                   $jsprevlink .= "document.gwquiz.newPage.value=\"$pageNumber\";"  if( $numProbPerPage && $numPages > 1 );
                my $jumpLinks = '';
                   $jsprevlink .= 'document.gwquiz.submit();';
                my $probRow = [ CGI::b("Problem") ];                
                for my $i ( 0 .. $#pg_results ) {
                    my $pn = $i + 1;                        
                    if( $i >= $startProb && $i <= $endProb ) {                        
                        push( @$probRow, CGI::b(" [ ")) if ($i == $startProb);
                        push( @$probRow, " &nbsp;" . CGI::a( {-href=>".", 
                                                              -onclick=>"jumpTo($pn);return false;"}, "$pn") . "&nbsp; " );
                        push(@$probRow, CGI::b(" ] ")) if ($i == $endProb);
                    } 
                    elsif ( ! ($i % $numProbPerPage) ) {
                        push(@$probRow, " &nbsp;&nbsp; ", " &nbsp;&nbsp; ", " &nbsp;&nbsp; ");
                    }
                }                     
                if( $numProbPerPage && $numPages > 1 ) {
                    my $pageRow = [ CGI::td([ CGI::b('Jump to: '), CGI::b('Page '),  CGI::b(' [ ' ) ]) ];                    
                    for my $i ( 1 .. $numPages ) {
                        my $pn = ($i == $pageNumber) ? $i : CGI::a({-href=>'javascript:' .  
                        	      "document.gwquiz.newPage.value=\"$i\";" . 'document.gwquiz.submit();'}, "&nbsp;$i&nbsp;");
                        my $colspan =  0;                       
                        if( $i == $pageNumber ) {
                            $colspan = ($#pg_results - ($i-1)*$numProbPerPage > $numProbPerPage) 
                                                     ?  $numProbPerPage  :  $#pg_results - ($i-1)*$numProbPerPage + 1;
                        } 
                        else {
                            $colspan = 1;
                        }
                        push( @$pageRow, CGI::td({-colspan=>$colspan, -align=>'center'},  $pn) );
                        push( @$pageRow, CGI::td( [CGI::b(' ] '), CGI::b(' [ ')] ) ) if ( $i != $numPages );
                    }
                    push( @$pageRow, CGI::td(CGI::b(' ] ')) );
                    unshift( @$probRow, ' &nbsp; ' );
                    $jumpLinks = CGI::table( CGI::Tr(@$pageRow),  CGI::Tr( CGI::td($probRow) ) );
                } 
                else {
                    unshift( @$probRow, CGI::b('Jump to: ') );
                    $jumpLinks = CGI::table( CGI::Tr( CGI::td($probRow) ) );
                }               
                print $jumpLinks,"\n";
                ### END PRINT JAVA LINKS 
                ##########################################################################################################################
                                

                my $problemNumber = 0;
                    
                ###########################################################################################################################
                #### FOR EACH PG_RESULTS : PRINT PROBLEM ORDER
                foreach my $i ( 0 .. $#pg_results ) {
                    
                    my $pg = $pg_results[$probOrder[$i]];
                       $problemNumber++;
                    
                    if( $i >= $startProb && $i <= $endProb ) { 
                        my $recordMessage = '';
                        my $resultsTable = '';
                           
                        if( $pg->{flags}->{showPartialCorrectAnswers}>=0 && $submitAnswers){
                            
                            if( $scoreRecordedMessage[$probOrder[$i]] ne "Your score on this problem was recorded." ) {
                                $recordMessage = CGI::span( {class=>"resultsWithError"}, "ANSWERS NOT RECORDED --", 
					                             $scoreRecordedMessage[$probOrder[$i]]);
                            }
                            $resultsTable = $self->attemptResults( $pg, 1, $will{showCorrectAnswers},
                                                                   $pg->{flags}->{showPartialCorrectAnswers} && 
                                                                   $canShowProblemScores,
                                                                   $canShowProblemScores, 1                        );
                        }
                        elsif ( $checkAnswers ) {
                            $recordMessage = CGI::span({class=>"resultsWithError"}, "ANSWERS ONLY CHECKED -- ", 
                                                                                    "ANSWERS NOT RECORDED");
                            $resultsTable = $self->attemptResults( $pg, 1, $will{showCorrectAnswers},
                                                                   $pg->{flags}->{showPartialCorrectAnswers} && 
                                                                   $canShowProblemScores, $canShowProblemScores, 1 );
                        } 
                        elsif ( $previewAnswers ) {
                            $recordMessage = CGI::span( {class=>"resultsWithError"}, "PREVIEW ONLY -- ANSWERS NOT RECORDED");
                            $resultsTable = $self->attemptResults($pg, 1, 0, 0, 0, 1);
                        }	    
                        
                        print CGI::start_div({class=>"gwProblem"});
                           
                        my $i1 = $i+1;
                        my $points = ($problems[$probOrder[$i]]->value() > 1) ? " (" . $problems[$probOrder[$i]]->value() . 
                                                                                " points)" :  " (1 point)";
                        print CGI::a({-name=>"#$i1"},"");
                        print CGI::strong("Problem $problemNumber."), "$points\n", $recordMessage;


                        #(ADW):  Remove the code that says "Note: You can earn partial credit on this problem."
                        if ($pg->{result}->{msg} =~ m/\s*You\s*can\s*earn\s*partial\s*credit\s*on\s*this\s*problem\s*/ ) {
                          print CGI::p($pg->{body_text});
                        }
                        else {
                          print CGI::p($pg->{body_text}), CGI::p($pg->{result}->{msg} ?  CGI::b("Note: ") 
                                                                                      : "", CGI::i($pg->{result}->{msg}));
                        }
                        ##### END (ADW) modification.
                        print CGI::p({class=>"gwPreview"}, CGI::a({-href=>"$jsprevlink"}, "preview problems"));
                        print $resultsTable if $resultsTable; 
                        print CGI::end_div();
                           
                        my $pNum = $probOrder[$i] + 1;
                           print CGI::hidden({-name=>"probstatus$pNum", -value=>$probStatus[$probOrder[$i]]});
                           print "\n", CGI::hr(), "\n";
                    }
                    else {
                        my $i1 = $i+1;
                        print CGI::a({-name=>"#$i1"},""), "\n";
                        my $curr_prefix = 'Q' . sprintf("%04d", $probOrder[$i]+1) . '_';
                        my @curr_fields = grep /^$curr_prefix/, keys %{$self->{formFields}};
                        
                        foreach my $curr_field ( @curr_fields ) {
                            print CGI::hidden({-name=>$curr_field, -value=>$self->{formFields}->{$curr_field}});
                        }
                        my $pNum = $probOrder[$i] + 1;
                           print CGI::hidden({-name=>"probstatus$pNum", -value=>$probStatus[$probOrder[$i]]});
                    }
                }
              
                print CGI::p($jumpLinks, "\n");
                print "\n",CGI::hr(), "\n";

                if( $can{showCorrectAnswers}) {
                    print CGI::checkbox(-name   =>"showCorrectAnswers", -checked=>$want{showCorrectAnswers},
                                                                        -label  =>"Show correct answers",     );
                } 

                if( $can{showSolutions}) {
                    print CGI::checkbox(-name    => "showSolutions", -checked => $will{showSolutions},
                                                                     -label   => "Show Solutions",     );
                }
                if( $can{showCorrectAnswers} or $can{showHints} or $can{showSolutions}) {
                    print CGI::br();
                }

                ##(ADW):  Change "Preview Test" to "Preview Problem" and put warnings around "Grade Test".
                print CGI::p( CGI::submit( -name=>"previewAnswers",  
                                           -label=>"Preview Problem" ), ( $can{recordAnswersNextTime} ?  
                                           "Only <B>ONE</B> Submission per quiz! ==>" . CGI::submit( -name=>"submitAnswers", -label=>"Grade Test" ) . "<== Only <B>ONE</B> Submission per quiz!" : ""),
                                         ( $can{checkAnswersNextTime} && ! $can{recordAnswersNextTime} ?
                                           CGI::submit( -name=>"checkAnswers", -label=>"Check Test" ) : " "),
                                         ( $numProbPerPage && $numPages > 1 && $can{recordAnswersNextTime} ? 
                                           CGI::br() . CGI::em("Note: grading the test grades " . 
                                           CGI::b("all") . " problems, not just those " . "on this page.") : " ") );
                print CGI::endform();
            }
                   
            if( $authz->hasPermissions($user, "view_answers")) {
                my $pastAnswersPage = $urlpath->newFromModule( "WeBWorK::ContentGenerator::Instructor::ShowAnswers", 
                                                                courseID => $ce->{courseName});
                my $showPastAnswersURL = $self->systemLink($pastAnswersPage, authen => 0);
                print "\n", CGI::start_form( -method=>"POST",
                                             -action=>$showPastAnswersURL,
                                             -target=>"WW_Info"),"\n", $self->hidden_authen_fields,"\n", 
                                              CGI::hidden(-name => 'courseID',  -value=>$ce->{courseName}), "\n",
                                              CGI::hidden(-name => 'problemID', -value=>($startProb+1)), "\n",
                                              CGI::hidden(-name => 'setID',  -value=>$setVName), "\n",
                                              CGI::hidden(-name => 'studentUser',    -value=>$effectiveUser), "\n",
                                              CGI::p( {-align=>"left"},
                                              CGI::submit(-name => 'action',  -value=>'Show Past Answers')   ), "\n",
                            CGI::endform();
            }
            
            
  
        ##########################################################################################################
        ##########################################################################################################
        #### TUTOR -  DISPLAY TUTORIAL / SESSION
        ##########################################################################################################
        #### 
        #### CONSTRUCT THE SESSION/SWV OBJECT AND DISPLAY 
        ####
                
                           
        ##########################################################################################################
        ##########################################################################################################
        ##########################################################################################################
        ##########################################################################################################

       
            
    
    return "";

}

sub getProblemHTML {
	
    my ( $self, $EffectiveUser, $setName, $setVersionNumber, $formFields, $mergedProblem, $pgFile ) = @_;
    my $r = $self->r;
    my $ce = $r->ce;
    my $db = $r->db;
    my $key =  $r->param('key');
    my $permissionLevel = $self->{permissionLevel};
	my $set  = $db->getMergedSetVersion( $EffectiveUser->user_id,  $setName, $setVersionNumber );
       die "set $setName,v$setVersionNumber for effectiveUser " .  $EffectiveUser->user_id . " not found." unless $set;
    my $psvn = $set->psvn(); 
    if( defined($mergedProblem) && $mergedProblem->problem_id ) {
        ## DO NOTHING    
    } 
    elsif ($pgFile) {
        $mergedProblem = WeBWorK::DB::Record::ProblemVersion->new(  set_id => $set->set_id,
                                                                    version_id => $set->version_id,
                                                                    problem_id => 0,
                                                                    login_id => $EffectiveUser->user_id,
                                                                    source_file => $pgFile,                       );
	}
    my $showCorrectAnswers = $self->{will}->{showCorrectAnswers};
    my $showHints          = $self->{will}->{showHints};
    my $showSolutions      = $self->{will}->{showSolutions};
    my $processAnswers     = $self->{will}->{checkAnswers};
    my $problemNumber = $mergedProblem->problem_id;
    my $pg =  WeBWorK::PG->new( $ce,
                                $EffectiveUser,
                                $key,
                                $set,
                                $mergedProblem,
                                $psvn,
                                $formFields, 
                                {  displayMode     => $self->{displayMode},
                                   showHints       => $showHints,
                                   showSolutions   => $showSolutions,
                                   refreshMath2img => $showHints || $showSolutions,
                                   processAnswers  => 1,
                                   QUIZ_PREFIX     => 'Q' . sprintf("%04d",$problemNumber) . '_', },  );
    if( $pg->{warnings} ne "") {
        push @{$self->{warnings}}, {  set     => "$setName,v$setVersionNumber",
                                      problem => $mergedProblem->problem_id,
                                      message => $pg->{warnings},                 };
	}
    if( $pg->{flags}->{error_flag}) {
        push @{$self->{errors}}, {  set     => "$setName,v$setVersionNumber",
                                    problem => $mergedProblem->problem_id,
                                    message => $pg->{errors},
                                    context => $pg->{body_text},                  };
        $pg->{body_text} = undef;
    }
    return    $pg;
}

sub problemListRow($$$) {

    my $self = shift;
    my $set = shift;
    my $Problem = shift;
    my $name = $Problem->problem_id;
    my $interactiveURL = "$name/?" . $self->url_authen_args;
    my $interactive = CGI::a({-href=>$interactiveURL}, "Problem $name");
    my $attempts = $Problem->num_correct + $Problem->num_incorrect;
    my $remaining = $Problem->max_attempts < 0  ? "unlimited"  : $Problem->max_attempts - $attempts;
    my $status = sprintf("%.0f%%", $Problem->status * 100); # round to whole number
	
    return CGI::Tr( CGI::td({-nowrap=>1}, [$interactive, $attempts, $remaining, $status, ]));
}


1;

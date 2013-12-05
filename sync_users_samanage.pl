#!/usr/bin/perl
#
# perl sync_users_samanage.pl
#
# Developed by Wilson Farrell for use within the Town of Cary, 
# based loosely on Import_Users_ZMC.pl provided by Samanage to the 
# Town of Cary.  
#
#    Copyright (C) 2013 Town of Cary, NC (Wilson Farrell, Developer)
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.

#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

# 
require 'common.pl';                # just some helper functions

use POSIX qw(strftime);
use Data::Dumper;                   # This should be in the standard Perl install
use MIME::Base64;                   # This should be in the standard Perl install
# some of these may need to be installed via cpan.  Your mileage may vary
use REST::Client;                   
use XML::Simple;                    

use Time::Local;
use Date::Format;
use Text::CSV_XS;
use Array::Utils qw(:all);

# Setup up some globals

# Setup the "say" output location (common.pl)
setupStdout("stdout_sync_");

# if you want to test the script so it only updates/adds one user to samanage, set this to 1, otherwise 0
$test_with_one = 0;

# if you want to test this script so it does not do any updates to samanage, set to 0, otherwise 1
$update_api = 1;

# You need a user with administrative privilege in Samanage to access the users API

$username = 'smadmin@myorg.org';
$password = 'passw0rd';

# Name of the host to use for the API
$api_host = 'myorg.samanage.com';

# where to find the above described csv
$location_of_csv = '../ADReport/ADForSAManage.csv';

# default area code for correcting phone numbers, will not overwrite
# areacode if existing number does not have 7 digits
# result will be (xxx) 123-4567
$areacoode = "919";

$eol = "\n";

# lets get started....

# stores users from samanage
$sam_users = ();

# stores departments from samanage
$sam_depts = ();

# stores roles from samanage
$sam_roles = ();

# stores sites from samanage (we don't currently do anything with this)
$sam_sites = ();

# stores list of hash of hashes of user data from AD (read from csv). 
$ad_users = ();

# maps samanage user id numbers to email addresses
$sam_ids_to_email = ();

# stored detected changes between what is in AD and what is Samanage.
# note that the script does not delete anyone, but is will disable
# users by changing their group to "Disabled Users".  As a result there
# is no delete list.
$changes = ();

# stores new users that need to be created in Samanage
$adds = ();

# id of the portal user
$portal_user_role_id = 0;

# id of the disabled user
$disabled_user_role_id = 0;

# Some variable for setting up the REAST client
$rest_client = undef;
$get_headers = ();
$post_headers = ();

# stores the list of accounts that should be ignored if they are either encountered in AD or samanage.
# populated from ignore_list.txt
$ignore_account_list = ();

# Some of our department names in AD are messy, this standardizes things so they match up to the 
# department names in Samanage
$translate_depts = {"Technology Services"=>"Technology Services",
		    "Administration"=>"Administration",
		    "Council"=>"Council",
		    "Engineering"=>"Engineering",
		    "Finance"=>"Finance",
		    "Fire"=>"Fire",
		    "Human Resources"=>"Human Resources",
		    "Inspections & Permits"=>"Inspections & Permits",
		    "Parks, Recreation & Cultural Resources"=>"Parks Recreation & Cultural Resources",
		    "Planning"=>"Planning",
		    "Police"=>"Police",
		    "Inspections and Permits"=>"Inspections & Permits",
		    "Public Works & Utilities"=>"Public Works & Utilities",
		    "Public Works & Utilties"=>"Public Works & Utilities",
		    "Public Works and Utilities"=>"Public Works & Utilities"};
			
			
# there is some stderr that I haven't quite figured out how to eliminate
# might as well timestamp it		       
print STDERR time2str("%c",time()) . $eol;			

sayErr("Building Ignore List");
build_ignore_list();

sayErr("Setting up REST Client");
$rest_client = setup_rest_client();

sayErr("Starting Import Users from Samanage");
get_current_sam_users();
#test_print_users();

sayErr("Starting Import Departments from Samanage");
get_current_sam_depts();
#test_print_depts();

sayErr("Starting Import Roles from Samanage");
get_current_sam_roles();
#test_print_roles();

#get_current_sam_sites();
#test_print_sites();

sayErr("Starting read of Users from AD CSV");

get_ad_users_from_csv();
#test_print_ad_users();

compare_lists();
#print "These will be added to Samanage$eol";
#test_print_adds();
execute_adds();

#print "These will be changed in Samanage$eol";
#test_print_changes();
execute_mods();

# reads in the ignore list; builds a hash for easy lookup
sub build_ignore_list() {
   open IGNORES, "< ignore_list.txt" or sayDie("cannot open ignore_list.txt");
   while ($line = <IGNORES>) {
	my $line = trim($line);
	if ($line =~ /.+\@.+/) {
	    $ignore_account_list->{trim(lc($line))} = 1;
	}
    }
   close IGNORES;
}

## Get Samanage current users
## Populate into struct $user_emails{$email}{field} = val
sub get_current_sam_users() {
    $resp = getXMLList("users","user");
    foreach my $key (keys %{$resp}) {
	my $this_email = trim(lc($resp->{$key}->{'email'}));
	$sam_users->{$this_email}->{id} = $key;
	$sam_users->{$this_email}->{name} = $resp->{$key}->{'name'};
	$sam_users->{$this_email}->{phone} = $resp->{$key}->{'phone'};
	$sam_users->{$this_email}->{site} = (exists $resp->{$key}->{'site'}) ? $resp->{$key}->{'site'}->{'id'} : 0;
	$sam_users->{$this_email}->{department} = (exists $resp->{$key}->{'department'}) ? $resp->{$key}->{'department'}->{'id'} : 0;
	$sam_users->{$this_email}->{role} = (exists $resp->{$key}->{'role'}) ? $resp->{$key}->{'role'}->{'id'} : 0;
	$sam_users->{$this_email}->{AD_Account_Name} = $resp->{$key}->{'custom_fields_values'}->{'AD_Account_Name'} if (exists $resp->{$key}->{'custom_fields_values'}->{'AD_Account_Name'});
	$sam_ids_to_email->{$key} = $this_email;
    }
}

# produce a hash table of AD users by email who are active
# if they are duplicate to one that is already in the list, it will be disregarded.
# the first duplicate in the list is used.
sub get_ad_users_from_csv () {
    my @ad_user_array = read_csv($location_of_csv);
    $total_count = 0;
    my $depts = ();
    foreach $href (@ad_user_array) {
	my $email = trim(lc($href->{Email}));
	if (exists $ad_users->{$email}) {
	    sayErr( "$email already listed for " . $href->{Username} . " other is: " . $ad_users->{$email}->{Username});
	} else {
	    $total_count ++;
	    if (uc(trim($href->{'Account Is Disabled'})) eq "FALSE") {
		$ad_users->{$email} = $href;

		if (!exists $depts->{$href->{Department}}) {
#		    sayErr("Dept: " . $href->{Department});
		    $depts->{$href->{Department}} = 1;
		}
		$ad_users->{$email}->{Department} = get_id_of_sam_dept($ad_users->{$email}->{Department});
		$ad_users->{$email}->{Phone} = fix_phone_number($ad_users->{$email}->{Phone});
		$ad_users->{$email}->{Name} = trim($ad_users->{$email}->{'First Name'}) . " " . trim($ad_users->{$email}->{'Last Name'});
		$ad_users->{$email}->{Username} = lc($ad_users->{$email}->{'Username'});
		$ad_users->{$email}->{'Last Name'} = trim($ad_users->{$email}->{'Last Name'});
		$ad_users->{$email}->{'First Name'} = trim($ad_users->{$email}->{'First Name'});
	    }
	}
    }
    sayErr("Total: " . scalar(@ad_user_array). " Usable: " .scalar(keys %{$ad_users}));
}

# fixes phone numbers
# if AD phone number is not 7 or 10 digits, 
# it will set phone number to "UPDATE IN AD"
sub fix_phone_number {
    my ($pn) = @_;
    $pn_digits = $pn;
    $pn_digits =~ s/\D//g;
    if (length($pn_digits) == 7) {
	return "(" . $areacode . ") " . substr($pn_digits,0,3) . "-" . substr($pn_digits,3,4);
    }
    if (length($pn_digits) == 10) {
	return "(" . substr($pn_digits,0,3) . ") ". substr($pn_digits,3,3) . "-" . substr($pn_digits,6,4);
    }
    return "UPDATE IN AD";
}

# compare the ad and samanages lists
# populate changes and adds
sub compare_lists() {
    #create a list of the ignores
    my @ignore_list = sort keys %{$ignore_account_list};    
   
    # create a temporary list of all the AD user emails
    # subtract out the ignore list from this list to create ad_emails
    my @tmp = sort keys %{$ad_users};
    my @ad_emails = array_minus(@tmp,@ignore_list);

    #create a temporary list of all the samanage user emails
    #subtract out the ignore list from this list to create sam_emails
    @tmp = sort keys %{$sam_users};
    my @sam_emails = array_minus(@tmp,@ignore_list);
    
    # do some more array "math" to find out those emails not in samanage,
    # not in AD, and those in both lists
    my @not_in_sam = array_minus(@ad_emails,@sam_emails);
    my @not_in_ad = array_minus(@sam_emails,@ad_emails);
    my @in_both_lists = intersect(@ad_emails,@sam_emails);

#    sayErr("Not in SAM");
#    sayErr(join($eol,@not_in_sam));

#    sayErr("Not in AD");
#    sayErr(join($eol,@not_in_ad));

    #Create the list of people to add people into samanage
    foreach my $email (@not_in_sam) {
	$adds->{$email}->{'first_name'} = $ad_users->{$email}->{'First Name'};
	$adds->{$email}->{'last_name'} = $ad_users->{$email}->{'Last Name'};
	$adds->{$email}->{'email'} = $email;
	$adds->{$email}->{'phone'} = $ad_users->{$email}->{'Phone'} if length(trim($ad_users->{$email}->{'Phone'})) >= 9;
	$adds->{$email}->{'department'} = $ad_users->{$email}->{'Department'} if (exists $ad_users->{$email}->{'Department'} && !$ad_users->{$email}->{'Department'} eq "");
	$adds->{$email}->{'role'} = "Portal User";
	$adds->{$email}->{'AD_Account_Name'} = $ad_users->{$email}->{'Username'};
	
    }
    
    #Create the list of people to disable in samanage
    #This is really just a a variation of update, since we only change 
    #their group membership
    foreach my $email (@not_in_ad) {
#	if ($sam_users->{$email}->{'role'} != $disabled_user_role_id && exists $sam_users->{$email}->{'AD_Account_Name'} && $sam_users->{$email}->{'AD_Account_Name'} ne ""){
	if ($sam_users->{$email}->{'role'} != $disabled_user_role_id){

	    my $id = $sam_users->{$email}->{'id'};
	    $changes->{$id}->{'role'} = "Disabled Users";
	}
    }
    
    #Create the list of updates that need to be made in samanage
    #We need to check whether something is set at all or just different than
    # the AD value
    foreach my $email (@in_both_lists) {
	my $id = $sam_users->{$email}->{'id'};
	if (! exists $sam_users->{$email}->{'name'} || $sam_users->{$email}->{'name'} ne $ad_users->{$email}->{'Name'}) {
	    $changes->{$id}->{'first_name'} = $ad_users->{$email}->{'First Name'};
	    $changes->{$id}->{'last_name'} = $ad_users->{$email}->{'Last Name'};
	}
	if (! exists $sam_users->{$email}->{'phone'} || $sam_users->{$email}->{'phone'} ne $ad_users->{$email}->{'Phone'} && (length(trim($ad_users->{$email}->{'Phone'})) >= 9)) {
	    $changes->{$id}->{'phone'} = $ad_users->{$email}->{'Phone'};
	}

	if (! exists $sam_users->{$email}->{'department'} || $sam_users->{$email}->{'department'} != $ad_users->{$email}->{'Department'}){
	    $changes->{$id}->{'department'} = $ad_users->{$email}->{'Department'};
	}


	if (! exists $sam_users->{$email}->{'role'} || $sam_users->{$email}->{'role'} == $disabled_user_role_id ){
	    $changes->{$id}->{'role'} = "Portal User";
	}

	if (! exists $sam_users->{$email}->{'AD_Account_Name'} || $sam_users->{$email}->{'AD_Account_Name'} ne $ad_users->{$email}->{'Username'}){
	    $changes->{$id}->{'AD_Account_Name'} = $ad_users->{$email}->{'Username'};
	}
	
    }
    
    
    
#    sayErr("In AD and SAM");
#    sayErr(join($eol,@in_both_lists));
}

#Take the things that need to be added to samanage and add them by creating the
#XML of the records and calling the API to add it
sub execute_adds() {
    my $count_success = 0;
    my $count = 0;
    foreach my $email (sort keys %{$adds}) {
	if ($test_with_one == 0 || ($test_with_one == 1 && $count < 1)) {
	    my $xml = create_xml($adds->{$email});
	    $count_success++ if (add_record_to_samanage($xml,'users'));
	}
	$count ++;
    }
    sayErr("$count_success of " . scalar(keys %{$adds}). " users added successfully");
}

#Take the things that need to be updated in samanage and update them by creating
# the XML of the records and calling the API to update it.
sub execute_mods() {
    my $count_success = 0;
    my $count = 0;
    foreach my $id (sort keys %{$changes}) {
	if ($test_with_one == 0 || ($test_with_one == 1&& $count < 1)) {
	    my $xml = create_xml($changes->{$id});
	    $count_success++ if (update_record_in_samanage($xml,'users',$id,$sam_ids_to_email->{$id}));
	}
	$count ++;
    }
    sayErr("$count_success of " . scalar(keys %{$changes}) . " users updated successfully");
}

#Creates the XML user document
sub create_xml {
    my ($href) = @_;
    $returnString = "<user>";
    
    $returnString = $returnString . create_xml_setter('first_name',$href->{first_name}) if (exists $href->{first_name});
    $returnString = $returnString . create_xml_setter('last_name',$href->{last_name}) if (exists $href->{last_name});
    $returnString = $returnString . create_xml_setter('email',$href->{email}) if (exists $href->{email});
    $returnString = $returnString . create_xml_setter('phone',$href->{phone}) if (exists $href->{phone});
    $returnString = $returnString . create_xml_setter('site',$href->{site}) if (exists $href->{site});
    $returnString = $returnString . create_xml_setter('department',$href->{department}) if (exists $href->{department});
    $returnString = $returnString . create_xml_setter('role',$href->{role}) if (exists $href->{role});
    $returnString = $returnString . create_xml_setter('AD_Account_Name',$href->{AD_Account_Name}) if (exists $href->{AD_Account_Name});
    
    $returnString = $returnString . "</user>";
    return $returnString;
}

# creates an XML tag of a data element of a user account field in samanage
# Special cases for nested elements (Department, Role, Custom fields, etc)
sub create_xml_setter {
    my ($key,$val) = @_;
    $beforeTag = "<" . $key . ">";
    $afterTag = "</" . $key . ">";
    
    $beforeTag = "<department><id>" if ($key eq "department");
    $afterTag = "</id></department>" if ($key eq "department");

    $beforeTag = "<role><name>" if ($key eq "role");
    $afterTag = "</name></role>" if ($key eq "role");
    
    $beforeTag = "<custom_field><AD_Account_Name>" if ($key eq "AD_Account_Name");
    $afterTag = "</AD_Account_Name></custom_field>" if ($key eq "AD_Account_Name");

    $beforeTag = "<site><id>" if ($key eq "site");
    $afterTag = "</id></site>" if ($key eq "site");

    return "$beforeTag$val$afterTag";
}

# Queries Samanage for the current list of departments
sub get_current_sam_depts() {
    $sam_depts = getXMLList("departments","department");
    
}

# gets samanage id of a department from the list we created
# translates as required for dept names that do not match the 
# ones we have set in samanage
sub get_id_of_sam_dept() {
    my ($dept_str) = @_;
    $dept_str = $translate_depts->{$dept_str};
    foreach my $key (keys %{$sam_depts}) {
	return $key if ($sam_depts->{$key}->{name} eq $dept_str);
    }
    return "";
}

# Queries samanage for the current list of roles, Sets the
# $portal_user_role_id and $disabled_user_role_id
sub get_current_sam_roles() {
    $sam_roles = getXMLList("roles","role");
    foreach $role_id (keys %{$sam_roles}) {
	if ($sam_roles->{$role_id}->{name} eq "Portal User") {
	    $portal_user_role_id = $role_id;
	}
	if ($sam_roles->{$role_id}->{name} eq "Disabled Users") {
	    $disabled_user_role_id = $role_id;
	} 
    }   	
}

# Queries Samanage for the current list of sites.  We currently 
# aren't doing anything with this since we don't have that data in AD
sub get_current_sam_sites() {
    $sam_sites = getXMLList("sites","site");
    
}


######## Print stuff out #######
# bunch of helper routines

sub test_print_users() {
    my $count = 1;
    foreach my $email (sort keys %{$sam_users}) {
	sayErr( $count . "," . $email . "," .
	    $sam_users->{$email}->{id} . "," .
	    "\"" . $sam_users->{$email}->{name} . "\"" . "," .
	    "\"" . $sam_users->{$email}->{phone} . "\"" . "," .
	    "\"" . $sam_users->{$email}->{AD_Account_Name} . "\"" . "," .
	    $sam_users->{$email}->{site} . "," .
	    $sam_users->{$email}->{department} . "," .
	    $sam_users->{$email}->{role});
	$count ++;
    }
}

sub test_print_ad_users() {
    my $count = 1;
    foreach my $email (sort keys %{$ad_users}) {
#	print join(",",keys %{$ad_users->{$email}}); 
	sayErr( $count . "," . $email . "," .
	    "\"" . $ad_users->{$email}->{'Display Name'} . "\"" . "," .
	    "\"" . $ad_users->{$email}->{'First Name'} . "\"" . "," .
	    "\"" . $ad_users->{$email}->{'Last Name'} . "\"" . "," .
	    "\"" . $ad_users->{$email}->{'Name'} . "\"" . "," .
	    "\"" . $ad_users->{$email}->{Username} . "\"" . "," .
	    "\"" . $ad_users->{$email}->{Phone} . "\"" . "," .
	    $ad_users->{$email}->{Department});
	$count ++;
    }
}

sub test_print_depts() {
    my $count = 1;
    foreach my $id (sort keys %{$sam_depts}) {
	sayErr($count . "," . $id .
	    "\"" . $sam_depts->{$id}->{name} . "\"" . "," .
	    "\"" . $sam_depts->{$id}->{description} . "\"");
	$count ++;
    }
}

sub test_print_roles() {
    my $count = 1;
    foreach my $id (sort keys %{$sam_roles}) {
	sayErr( $count . "," . $id .
	    "\"" . $sam_roles->{$id}->{name} . "\"" . "," .
	    "\"" . $sam_roles->{$id}->{description} . "\"");
	$count ++;
    }
}

sub test_print_sites() {
    my $count = 1;
    foreach my $id (sort keys %{$sam_sites}) {
	sayErr( $count . "," . $id .
	    "\"" . $sam_sites->{$id}->{name} . "\"" . "," .
	    "\"" . $sam_sites->{$id}->{description} . "\"");
	$count ++;
    }
}

sub test_print_adds() {
    foreach my $email (sort keys %{$adds}) {
       
	foreach my $key (sort keys %{$adds->{$email}}) {
	    sayErr( $key . "->\"". map_value_for_printing($key,$adds->{$email}->{$key}) . "\"");
	}
	print $eol;
    }
}    

sub test_print_changes() {
    foreach my $id (sort keys %{$changes}) {
	print $id . " (" . $sam_ids_to_email->{$id} . "):$eol";
	foreach my $key (sort keys %{$changes->{$id}}) {
	    print $key . "->\"". map_value_for_printing($key,$changes->{$id}->{$key}) . "\"$eol";
	}
	print $eol;
    }
}    

sub map_value_for_printing() {
    my ($key,$value) = @_;
    $return = $value;
    $return = $value . "(" . $sam_sites->{$value}{name} . ")" if ($key eq "site");
    $return = $value . "(" . $sam_depts->{$value}{name} . ")" if ($key eq "department");
    $return = $value . "(" . $sam_roles->{$value}{name} . ")" if ($key eq "role");
    return $return;
}

###########################################################################################
#
#  Set up a REST client
#
#
sub setup_rest_client {
    $rest_client = REST::Client->new(timeout => 10);
    $rest_client->getUseragent->ssl_opts(verify_hostname => 0,SSL_verify_mode => SSL_VERIFY_NONE);
    $rest_client->getUseragent->show_progress(2);
    $get_headers = {Accept => 'application/vnd.samanage.v1+xml', Authorization => 'Basic ' . encode_base64($username . ':' . $password)};
    $post_headers = {'Content-Type' => 'text/xml', Authorization => 'Basic ' . encode_base64($username . ':' . $password)};
    return $rest_client;
}

# query the samanage API for a list of things.  Get 100 at a time, since the 
# API will not support more than that
sub getXMLList() {
    my ($module,$outerElement) = @_;
    my $numrecords = 0;
    my $numrequested = 0;
    my $page = 1;

    my %returnHash = ();

    do {
	sayErr("Getting page $page from $module; $numrequested requested");
	$rest_client->GET("https://" . $api_host ."/". $module .".xml?page=$page", $get_headers);  
	sayDie("[".$rest_client->responseCode."] ".$rest_client->responseContent) if ($rest_client->responseCode != 200);
	sayErr("Calling XMLin on page $page");
	my $tmpHash = XMLin($rest_client->responseContent(),KeyAttr => [id]);
	
	sayErr("Got page $page");
	$numrequested += 100;
	if ($numrecords == 0) {
	    if (exists $tmpHash->{'total_entries'}) {
		$numrecords = $tmpHash->{'total_entries'};
		sayErr("looking for $numrecords records from samanage");
	    }
	}

	my %newHash = (%returnHash, %{$tmpHash->{$outerElement}}); %returnHash = %newHash;
#	@returnHash{keys %{$tmpHash}} = values %{$tmpHash};
	$page ++;
    } until $numrecords <= $numrequested;
    return \%returnHash;
}

# add a record to samanage
sub add_record_to_samanage() {
    my ($xml,$module) = @_;
    sayErr("sending XML to Samanage ($module): $xml$eol");
    if ($update_api) {
	$rest_client->POST('https://' . $api_host . '/' . $module . '.xml', $xml, $post_headers);
	if (check_for_api_errors()) {
	    sayErr("record added $module successfully.");
	    return 1;
	} else {
	    sayErr("record failed to add to $module");
	    return 0;
	}
    }
    return 1;
}

# update a record in samanage
sub update_record_in_samanage() {
    my ($xml,$module,$id,$desc) = @_;
    sayErr("sending XML to Samanage ($module,$id,$desc): $xml$eol");
    if ($update_api) {
	sayErr('calling https://' . $api_host . '/' . $module . '/'. $id . '.xml');
	$rest_client->PUT('https://' . $api_host . '/' . $module . '/'. $id . '.xml', $xml, $post_headers);
	if (check_for_api_errors()) {
	    sayErr("record updated in $module successfully.");
	    return 1;
	} else {
	    sayErr("record failed to update in $module");
	    return 0;
	}
    }
    return 1;
}

# looks for API errors; return 0 if one is detected
# otherwise 1
sub check_for_api_errors() {
    my $rcode = $rest_client->responseCode();
    my $rcontent = $rest_client->responseContent();
    if (($rcode != 200) && ($rcode != 201)) {
	sayErr("failed: $rcode");
	return 0;
    } elsif (grep /<error>/, $rcontent) {
	my $errxml = XMLin($rcontent);
	sayErr("error: $errxml->{error}");
	return 0;
    } 
    return 1;
} 



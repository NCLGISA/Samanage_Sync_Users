sync_samanage_users
===================

The purpose of this script is to synchronize users between a list of
Active Directory users and users in the Samanage IT Service Desk web based 
application.  This script was developed by a customer of that company.  It is
intended to executed once a day.

This script depends on a CSV of active AD users being created before this 
script is executed.  The script will assume that anything in the list, 
but not in the ignore list will need to be added (or enabled if previously 
disabled) to samamage, unless the "Account Is Disabled" field is "FALSE".  

If you want a subset of your AD users in samanage
you will need to filter your list when you create the CSV file.  The script
will however ignore any AD entry without an email address, since you have 
to have an email address to be a samanage user.  If there is a user in the
with an email address that has already be found in the AD csv, it will 
use the first entry with that email, ignoring subsequent.

Here is a typical entry in that file
"First Name","Last Name","Username","Email","Department","Phone","Account Is Disabled"
"Fred","Smith","fsmith","Fred.Smith@myorg.org","Personnel Dept","555-5555","False"

Samanage's API definition can be found at 
http://www.samanage.com/api/index.html

Please direct any questions about this API to them.

There are some global variables you will want to set in the beginning part 
of the sync_users_samanage.pl script.  They should be self explanatory.



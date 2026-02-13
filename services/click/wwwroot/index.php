<?php

# We need a database.
# And a user account, for that matter.

#mysql_connect... how do you do that again?

#die('wat');

session_start();
require('include.php');

#die("woah");

if(empty($_SESSION['Timezone']))
{
#	$XML = 
#simplexml_load_file("http://ipinfodb.com/ip_query.php?ip={$_SERVER['REMOTE_ADDR']}&timezone=true");
#	$_SESSION['Timezone'] = (string)$XML->TimezoneName[0];
}


# Now what?
# I wanna be able to click on the screen to start typing.

#die("hi");

$Page = replace_input($_GET['page']);

# I should probably get around to changing page to path.
# That way derp can be page.
# Maybe even revamp the database for more statistical information.

$Derp = replace_input($_GET['p']);
if(empty($Derp))
	$Derp = 1;

ob_start();
include("nav.php");
$Nav = ob_get_contents();
ob_end_clean();

require('template.php');
echo Template('template.html');

?>

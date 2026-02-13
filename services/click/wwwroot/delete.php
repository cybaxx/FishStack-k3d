<?php

session_start();
require('include.php');

if(in_array($_SESSION['Click']['User'], array('click', 'rachel', 'wetfish', 'guthbrandr')))
{
	$ID = stripslashes($_GET['id']);
	$ID = filter_var($ID, FILTER_SANITIZE_SPECIAL_CHARS);
	
	mysql_query("Update `Pages` set `Deleted`='1' where `ID`='$ID'");
	
	echo "Post deleted.";
}

?>

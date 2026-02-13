<?php

include("functions.php");

$Hash = mysql_real_escape_string(trim($_GET['hash'], '/'));


$Query = mysql_query("Select `Content` from `Posts` where `Hash`='$Hash'");
list($Content) = mysql_fetch_array($Query);

if($Content)
	echo stripslashes($Content);
	
?>

<?php

session_start();
require('include.php');

$ID = replace_input($_GET['id']);

$Query = mysql_query("Select `Page`,`Time`,`Data`,`Deleted`
						from `Pages`
						where `ID`='$ID'
						limit 1");
						
list($Page, $Time, $Data, $Deleted) = mysql_fetch_array($Query);

if($Time and (!$Deleted))
{
    echo replace_output($Data);
}

?>

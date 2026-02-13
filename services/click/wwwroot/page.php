<?php

require('include.php');

$Page = replace_input($_GET['page']);

$Query = mysql_query("Select `Data` from `Pages` where `Page`='$Page'");
list($Data) = mysql_fetch_array($Query);

if($Data)
{
    echo replace_output($Data);
}
else
{
	echo "There's nothing here yet.";
}

?>

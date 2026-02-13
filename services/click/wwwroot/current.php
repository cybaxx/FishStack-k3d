<?php

session_start();
require('include.php');


if($_SESSION['Timezone'])
	date_default_timezone_set($_SESSION['Timezone']);


$Page = replace_input($_GET['page']);

$Query = mysql_query("Select `ID`,`Time`,`Data`
						from `Pages`
						where `Page`='$Page'
						and `Deleted`='0'
						order by `ID`
						desc limit 1");
						
list($ID, $Time, $Data) = mysql_fetch_array($Query);

if($ID)
{
	$Time = date("G:i:s T", $Time);

	echo "<div class='view'><a href='/view.php?id=$ID'>$Time</a></div>";
	
	$PotentialURL = trim(str_replace(array('&nbsp;', '<br>', '<', '>'), ' ', $Data));
	
	if(filter_var($PotentialURL, FILTER_VALIDATE_URL))
		$Data = str_replace($PotentialURL, "<a href='$PotentialURL' target='_blank'>$PotentialURL</a>", $Data);
	else
	{
		foreach(explode(" ", str_replace(array('&nbsp;', '<br>', '<', '>'), ' ', $Data)) as $URL)
		{
			if(filter_var($URL, FILTER_VALIDATE_URL))
				$Data = str_replace($URL, "<a href='$URL' target='_blank'>$URL</a>", $Data);
		}
	}

    echo replace_output($Data);
}

?>

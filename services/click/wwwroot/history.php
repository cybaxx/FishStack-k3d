<?php

session_start();
require('include.php');
require('paginate.php');


if($_SESSION['Timezone'])
	date_default_timezone_set($_SESSION['Timezone']);


$Page = replace_input($_GET['page']);

$Query = "Select `ID`,`Time`,`Data`
			from `Pages` 
			where `Page`='$Page'
			and `Deleted`='0'
			order by `ID`
			desc";

list($Results, $Links) = Paginate($Query, 25, $_GET['p'], $_SERVER['QUERY_STRING'], 1);

if($Results)
{
	foreach($Results as $Result)
	{
		list($ID, $Time, $Data) = $Result;
		
		echo "<div style='clear:both'></div>";

		$Toggle++;

		if($Toggle % 2 == 1)
			echo "<div style='background-color:#140526;'>";
		else
			echo "<div>";
		
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
		echo "</div>";	
	}
	
	echo "<hr /><center>$Links</center>";
}


?>

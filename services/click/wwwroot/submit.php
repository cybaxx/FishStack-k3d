<?php

require('include.php');

//echo "where is the post";
//echo ini_get('post_max_size'); 
//echo ini_get('upload_max_filesize');

if($_POST['please'] == 'asdhAsjdalk' . 'asokjAa(Aaajs' . 'sksA2alA;sak')
{
	if($_POST)
	{
        $Page = replace_input($_GET['page']);
		$Time = time();
		$IP = $_SERVER['REMOTE_ADDR'];
		$Data = stripslashes($_POST['data']);
		$Data = mysql_real_escape_string($Data);
		
		//echo "is it being sent";	

		if(in_array(trim(str_replace('&nbsp;', ' ', $Data)), array("", "<br>", "<br />", "Care to write something?")))
		{
			# Useless content.
		}
		else
		{
			mysql_query("Insert into `Pages` values ('', '$Page', '$Time', '$IP', '$Data', '')");
			
			if(mysql_error())
				echo mysql_error();
		}
	}
}

?>

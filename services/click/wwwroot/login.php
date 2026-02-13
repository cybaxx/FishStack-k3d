<?php

session_start();
require('functions/table.php');

if($_POST)
{
	$FTP['server'] = "wetfish.net";
	$FTP['user'] = $_POST['Name'];
	$FTP['password'] = $_POST['Password'];

	if($_SESSION['Clicked']['Failed'] > 8)
	{
		echo "You've failed to login too many times. Please try again later.";
	}
	else
	{
		$FTP['Connection'] = ftp_connect($FTP['server']) or die("Couldn't connect to {$FTP['server']}"); 

		// try to login
		if(@ftp_login($FTP['Connection'], $FTP['user'], $FTP['password']))
		{
			echo "Authentication successful.";
			$_SESSION['Click']['User'] = $FTP['user'];
		}
		else
		{
			echo "Couldn't connect as {$FTP['user']}";
			$_SESSION['Click']['Failed']++;
		}
	}
	
	/*
	# Put username, IP, and time in login database
	# use sqlite?
	# keep track of failed logins too
	
	echo "<pre>";
	print_r(array($_POST['Name'], $_POST['Password'], $Error));
	*/
}
else
{
	echo "<form method='post'>";
	echo Table(	"{Name | <input type='text' name='Name' />}".
				"{Password | <input type='password' name='Password' />}".
				"{<input type='submit' value='Submit' /> }");
	echo "</form>";
}

?>
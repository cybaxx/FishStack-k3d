<?php

session_start();
require('include.php');

?>

<html>
	<head>
	<meta http-equiv="Content-Type" content="text/html; charset=utf-8">	
		<script src='https://ajax.googleapis.com/ajax/libs/jquery/1.4.4/jquery.min.js'></script>
		<script src='https://ajax.googleapis.com/ajax/libs/jqueryui/1.8.6/jquery-ui.min.js'></script>
		<link rel="stylesheet" href="https://ajax.googleapis.com/ajax/libs/jqueryui/1.7.2/themes/base/jquery-ui.css" type="text/css" /> 

		<style>
			#click-header { font-family: Tahoma,Helvetica,Sans-serif; font-size:10pt; }
			#click-submit { display:none }
		</style>
		
		<script>
			function Render()
			{
				var HTML = $('#click-content').html();
				
				HTML = HTML.replace(/&amp;/g, '&');
				HTML = HTML.replace(/&lt;/g, '<');
				HTML = HTML.replace(/&gt;/g, '>');
				
				$('#click-content').html(HTML);
			}
			
			function UnRender()
			{
				var HTML = $('#click-content').html();
				
				HTML = HTML.replace(/&/g, '&amp;');
				HTML = HTML.replace(/</g, '&lt;');
				HTML = HTML.replace(/>/g, '&gt;');
				
				$('#click-content').html(HTML);
			}
			
			function Submit()
			{
				$('#click-content').css('background-image', "url(/super.gif)");
			
				$.post('edit.php?id=<?php echo $_GET['id']; ?>', {data: $('#click-content').html() }, function()
				{
					// /me farts
					$('#click-content').css('background-image', "url()");
				});
			}
		
			$(document).ready(function()
			{
				$('#click-edit').click(function(event)
				{
					$('#click-content').attr('contenteditable', 'true');
					$('#click-submit').fadeIn();
					
				});
				
				$('#click-submit').click(function(event)
				{
					Submit();
				});
			});
		</script>
	</head>
	
	<body>
		<div id='click-header'>
			<a href='/'>Click Home</a> |
			<a href='/recent.php'>Recent Clicks</a> | 
			<a href='javascript:Render()' style='font-weight:bold'>Render HTML</a> | 
			<a href='javascript:UnRender()' style='font-weight:bold'>UnRender HTML</a>
	
<?php

$ID = replace_input($_GET['id']);

$Query = mysql_query("Select `Page`,`Time`,`Data`,`Deleted`
						from `Pages`
						where `ID`='$ID'
						limit 1");
						
list($Page, $Time, $Data, $Deleted) = mysql_fetch_array($Query);

if($Time and (!$Deleted or $_SESSION['Click']['User']))
{
	$Time = date("G:i:s T", $Time);

	echo "<!-- Start Click Nav --> <div style='float:right' id='click-nav'>";

	if(in_array($_SESSION['Click']['User'], array('click', 'rachel', 'wetfish', 'guthbrandr')))
	{
		echo "	<a href='#Submit' id='click-submit'>Submit</a>
				&emsp;
				<a href='#Edit' id='click-edit'>Edit</a>
				&emsp;
				<a href='delete.php?id=$ID'>Delete</a>
			";
	}
	else
	{
		echo "&emsp;<a href='/login.php' id='click-login'>Login</a>";
	}
	
    $Data = replace_output($Data);
	echo "&emsp;<a href='/$Page' id='click-thread'>View Thread</a>";
	echo "<!-- Close Click Nav --> </div>";
	echo "<!-- Close Click Header --> <hr /></div>";
	echo "<div id='click-content'>$Data</div>";
}

?>
	<hr />
	
	<center>
		<iframe id='leader-friend' 
				src='https://ads.wetfish.net/friendship/leader.html'
				style='width:750px; height:115px; border:0; outline:0; overflow:hidden;'
				scrolling="no"></iframe>
	</center>

	</body>
</html>

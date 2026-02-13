<html>
	<head>
		<title>All it takes is a click.</title>
		
		<style>
			body { margin:0; background:#000; color: #fff; font-family: Tahoma,Helvetica,Sans-serif; font-size:10pt; margin-left:4%; margin-right:4%; }
			a { color:#E87EE1; text-decoration: none; }
			a:hover { text-decoration: underline; }
			
			a.title { color:#FFF; font-weight:bold; }
			a.user { color:#E87EE1; font-weight:bold; }
			
			div.superborder
			{	background-image:url('/super.gif');
				font-size:16pt;
				font-weight:bold;
				margin-bottom:8px;
				border-bottom: 1px solid #000;
				border-right: 1px solid #000;
				border-left: 1px solid #000;
                border-bottom-right-radius: 8px;
                border-bottom-left-radius: 8px; 
				-moz-border-radius-bottomleft:8px;
				-moz-border-radius-bottomright:8px;
				-webkit-border-bottom-left-radius:8px;
				-webkit-border-bottom-right-radius:8px; }
		

			div.supernav
			{	background-image:url('/background.png'); 
				padding:8px;

				border-bottom: 1px solid #98b3cd;
				border-right: 1px solid #98b3cd;
				border-left: 1px solid #98b3cd;
                border-bottom-right-radius: 8px;
                border-bottom-left-radius: 8px;
				-moz-border-radius-bottomleft:8px;
				-moz-border-radius-bottomright:8px;
				-webkit-border-bottom-left-radius:8px;
				-webkit-border-bottom-right-radius:8px; }
		
			div.body { margin-left:3%; margin-right:3%; }
			
			div.title { font-weight:bold; font-size:24pt; }
			#input { border:1px #fff dashed; outline:0; padding:4px; }
			#form { padding-top:8px; margin:0; }
		</style>
		
		<script src='/jquery-1.4.2.min.js'></script>
		<script src='/jquery-ui-1.8.4.min.js'></script>
		<link href='/jquery-ui-1.8.4.css' rel='stylesheet' type='text/css' />
	</head>
	
	<body>
		<?php include("nav.php"); ?>
		
		<div class='body'>
			<a href='/'>Click Home</a> |
			<a href='/recent.php'>Recent Clicks</a>
			
			<hr />
			
			<div class='title'>Recent Clicks</div>

			<?php
			
			require('include.php');
			require('paginate.php');
			
			
			$Query = "Select `ID`, `Page`,`Time`,`Data`
						from `Pages` 
						where `Deleted`='0'
						order by `ID`
						desc";
			
			list($Results, $Links) = Paginate($Query, 25, $_GET['p'], $_SERVER['QUERY_STRING']);

			if($Results)
			{
				foreach($Results as $Result)
				{
					list($ID, $Page, $Time, $Data) = $Result;

					if($Page == '')
						$PageText = "Main Page";
					else
						$PageText = $Page;
						
					echo "<div style='clear:both'></div>";

					$Toggle++;

					if($Toggle % 2 == 1)
						echo "<div>";
					else
						echo "<div style='background-color:#140526;'>";
					
					$Time = date("G:i:s T", $Time);
					
					echo "	<div style='float:right;'>
								Posted on <a href='/$Page'>$PageText</a>
								at <a href='/view.php?id=$ID'>$Time</a>
							</div>";
					
					$PotentialURL = trim(str_replace(array('&nbsp;', '<br>'), ' ', $Data));
					
					if(filter_var($PotentialURL, FILTER_VALIDATE_URL))
						$Data = str_replace($PotentialURL, "<a href='$PotentialURL' target='_blank'>$PotentialURL</a>", $Data);
					else
					{
						foreach(explode(" ", str_replace(array('&nbsp;', '<br>'), ' ', $Data)) as $URL)
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
		</div>
	</body>
</html>

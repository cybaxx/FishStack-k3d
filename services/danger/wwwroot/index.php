<?php

include("functions.php");

//helo

//contenteditable
//for pasting


//with submit

function RandomButton()
{
	$Options = array("Sex", "Bubbles", "Friendship", "Drugs", "Happy", "Sabmit", "Danger", "Death", "Salvation");
	shuffle($Options);
	
	echo $Options[0];
}
	
if($_POST)
{
	$HTML = $_POST['html'];
	$Site = getenv('SITE_URL');
	
	// get images
	
	$Length = strlen($HTML);
	$Hash = md5($HTML);
	
	if($Length != 1)
		$Plural = "s";

	$Stuff = array(	"Your post is $Length character{$Plural} long.",
					"With an MD5 hash of $Hash",
					"",
					"<a href='https://wiki.wetfish.net '>Embed Code</a>",
					"<input type='text' value='embed[https://$Site/$Hash]' size='60' />",
					"<a href='https://$Site$Hash'>Dangerfish Page</a>",
					"<input type='text' value='https://$Site/$Hash' size='60' />");
					
	foreach($Stuff as $Line)
	{
		echo "<b>$Line</b><br />";
	}

	// Insert to database
	
	$Query = mysql_query("Select `Content` from `Posts` where `Hash`='$Hash'");
	list($Content) = mysql_fetch_array($Query);
	
	if(empty($Content))
	{
		$Author = $_SERVER['REMOTE_ADDR'];
		$Content = mysql_real_escape_string($_POST['html']);
		$Time = time();
	
		mysql_query("Insert into `Posts` values ('$Hash', '$Author', '$Content', '$Time')");
	}
	
	//echo stripslashes($_POST['html']);
}
else
{
	$Hash = mysql_real_escape_string(trim($_GET['hash'], '/'));
	$Page = explode('/', $Hash);
	
	switch($Page[0])
	{
		case "recent":
			$Query = mysql_query("Select * from `Posts` order by `Time` desc limit 50");
			while(list($QueryHash, $QueryAuthor, $QueryContent, $QueryTime) = mysql_fetch_array($Query))
			{
				$Length = strlen($QueryContent);
				
				date_default_timezone_set('America/New_York');
				$Time = date("F j\, Y G:i:s", $QueryTime)." EST";
			
				$Content .= "<tr>
								<td><b><a href='/$QueryHash'>$QueryHash</a></b></td>
								<td><b><a href='/author/$QueryAuthor'>$QueryAuthor</b></td>
								<td><b>$Length</b></td>
								<td><b>$Time</b></td>
							</tr>";
			}
			
			$Content = "<table>
							<tr>
								<td><b>Hash</b></td>
								<td><b>Author</b></td>
								<td><b>Length</b></td>
								<td><b>Time</b></td>
							</tr>
							$Content
						</table>";
						
			$Editable = "contenteditable=false";
		break;
	
		case "author":
			$Author = mysql_real_escape_string($Page[1]);
		
			$Query = mysql_query("Select * from `Posts` where `Author`='$Author' order by `Time` desc limit 50");
			while(list($QueryHash, $QueryAuthor, $QueryContent, $QueryTime) = mysql_fetch_array($Query))
			{
				$Length = strlen($QueryContent);
				
				date_default_timezone_set('America/New_York');
				$Time = date("F j\, Y G:i:s", $QueryTime)." EST";
			
				$Content .= "<tr>
								<td><b><a href='/$QueryHash'>$QueryHash</a></b></td>
								<td><b><a href='/author/$QueryAuthor'>$QueryAuthor</b></td>
								<td><b>$Length</b></td>
								<td><b>$Time</b></td>
							</tr>";
			}
			
			$Content = "<table>
							<tr>
								<td><b>Hash</b></td>
								<td><b>Author</b></td>
								<td><b>Length</b></td>
								<td><b>Time</b></td>
							</tr>
							$Content
						</table>";
						
			$Editable = "contenteditable=false";
		break;
	
		default:
			$Query = mysql_query("Select `Content` from `Posts` where `Hash`='$Hash'");
			list($Content) = mysql_fetch_array($Query);

			if($Content)
				$Content = stripslashes($Content);
			else
			{
				$Content = "Are you ready to get <b>DANGEROUS?</b><br /><br />
					This is a contenteditable div, you can paste all sorts of fun stuff into it, complete with URL for <a href='https://wiki.wetfish.net/'>sharing</a>.<br /><br />
					<span style='font-size:16pt; font-weight:bold;'>But what kind of fun stuff?</span><br />
					HTML formatting/images from other pages,<br />
					Formatting from rich text editors,<br />
					Malicious javascript,<br />
					AND SO MUCH MORE!!!!!!!!";
			}
			
			$Editable = "contenteditable=true";
		break;
	}
	
?>

<html>
	<head>
		<title>dangerfish</title>
	
		<meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
		<link rel="/stylesheet" type="text/css" href="jquery-ui.css"/>
		<link href="/jetpack.css" rel="stylesheet" type="text/css" />
		<script type='text/javascript' src='/jquery-1.4.2-min.js'></script>
		<script type="text/javascript" src="/jquery-ui.js"></script>
				
		<script>

			var Jetpack = new Object;
			
			Jetpack.Window = function(Input)
			{
				var Selector = "#jetpack[window='"+Input.name+"']";
					
				if($(Selector).length) // If the window has already been created.
				{
					$(Selector + ' > div#title').html(Input.title);
					$(Selector + ' > div#content').html(Input.contents);
				}
				else // Create new window.
				{
					Jetpack.title = "<div id='title'>" + Input.title + "</div>";
					Jetpack.contents = "<div id='content'>" + Input.contents + "</div>";
				
					Jetpack.window = "<div id='jetpack' window='" + Input.name + "'>" + Jetpack.title + Jetpack.contents + "</div>";
				
					$('body').append(Jetpack.window);
					
					// spawn on active part of the screen
					
					if('resize' in Input)
						$(Selector).resizable().draggable();
					else
						$(Selector).draggable();

					$(Selector).fadeIn('slow');
				}
			}

			function Submit()
			{
				$.post('index.php', {html: $('#dangerbox').html() }, function(Happy)
				{
					Jetpack.Window({
								name: 'Just A Window',
								title: '',
								contents: Happy,
								resize: true
							 });
				});
			}
			
			function Render()
			{
				var HTML = $('#dangerbox').html();
				
				HTML = HTML.replace(/&amp;/g, '&');
				HTML = HTML.replace(/&lt;/g, '<');
				HTML = HTML.replace(/&gt;/g, '>');
				
				$('#dangerbox').html(HTML);
			}
			
			function UnRender()
			{
				var HTML = $('#dangerbox').html();
				
				HTML = HTML.replace(/&/g, '&amp;');
				HTML = HTML.replace(/</g, '&lt;');
				HTML = HTML.replace(/>/g, '&gt;');
				
				$('#dangerbox').html(HTML);
			}
			
		</script>
	</head>
	
	<body>
		<a href='/' style='font-weight:bold'>What?</a> | 
		<a href='/recent' style='font-weight:bold'>Recent Posts</a> | 
		<a href='javascript:Render()' style='font-weight:bold'>Render HTML</a> | 
		<a href='javascript:UnRender()' style='font-weight:bold'>UnRender HTML</a>
		
		<br /><br />
	
		<div id='dangerbox' <?php echo $Editable ?>>
			<?php echo $Content ?>
		</div>
		
		<br />
		
		<input type='button' value='<?php RandomButton(); ?>' onClick='Submit()' />
	</body>
</html>
<?php

}

// Yuck!

?>

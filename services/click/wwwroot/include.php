<?php

// You gotta make a config file!
require("config.php");

mysql_connect(MYSQL_HOST, MYSQL_USER, MYSQL_PASSWORD);
mysql_select_db(MYSQL_DATABASE);

function replace_input($input)
{
    $output = stripslashes($input);
    $output = filter_var($output, FILTER_SANITIZE_SPECIAL_CHARS);
    $output = trim($output, "/");

    return $output;
}

function replace_output($input)
{
    $output = str_ireplace('icanhazchat.com/pibdgaf', 'wetfish.net', $input);
    $output = str_ireplace('http://', 'https://', $input);
    
    return $output;
}

?>

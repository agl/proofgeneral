<?php
  require('functions.php3');
  require('elispmarkup.php3');
  $filename=$HTTP_GET_VARS["file"];
  $title=$HTTP_GET_VARS["title"];
  $expanded=$HTTP_GET_VARS["expanded"];
  if ($title=="") { $title = $filename; };
  small_header($title);
  print "<pre>\n";
  /* I hope this is enough to prevent access outside cwd */
  if (substr($filename,0,1)=="." or 
      substr($filename,0,1)=="/" or
      substr($filename,0,1)=="~") {
     print "Sorry, can't show you that file!\n"; 
  } elseif (substr($filename,-3)==".el") {
     elisp_markup($filename,"fileshow.php");
  } else {
     outline_markup($filename,"fileshow.php",$expanded);
  }
  print "</pre>\n";
  print "<hr>";
  click_to_go_back();
  footer();
?>

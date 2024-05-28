<?php
header("X-Test-Repeated: 1");
header("X-Test-Repeated: 2", false);
header("X-Test-No-Colon");
header("X-Test-No-Value:");
header("X-Test-No-Value-Whitespace: ");
header("X-Test-Multiple-Colons: value:with:colons");
header("X-Test-No-Whitespace:value");
?>
<!DOCTYPE html>
<html>

<head>
  <title>PHP Test</title>
</head>

<body>
  Hello, <?php echo $_GET["name"]; ?>!
  <?php error_log("Hello, CGI stderr!"); ?>
  <?php phpinfo(); ?>
</body>

</html>

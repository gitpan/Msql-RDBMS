#!/usr/bin/perl

&mkcatalog();

if ($ARGV[0] eq '--catalog-only') {
  $ARGV[0] = $ARGV[1];
  $#ARGV = 0;
  $catonly = 1;
}

while (<ARGV>) {

  chop;
  next unless $_;
  next if /^#/;
    if (/^table:/) {

      if ($def) {
	if ($catonly) {
	  print $tables, $columns, $keys, $links;
	} else {
	  print $drop,$head,$def,")\n\\g\n",$tables,$columns,$keys,$links;
	}
      }

      ($null, $table, $description, $seehtml) = split(":");
      

      $drop = "DROP TABLE $table\n\\g\n";
      $head = "CREATE TABLE $table (\n";
      $def = "";
      
      $tables = "INSERT INTO systables\n" . 
	"   (tbl_name, tbl_description, tbl_seehtml)\n" .
	  "   VALUES ('$table', '$description', '$seehtml')\n\\g\n";
      $columns = "";
      $keys = "";
      next;
    } else {
      $def .= ", \n" if $def;
    }

  ($column, $type, $len, $args, $caption, 
   $keytype, $link, $query, $disp, $lnklabel)  = split(":");
  
  $type =~ s/money/real/ig;

  $def .= "   $column $type";
  $def .= " ($len)" if $len;
  $def .= " $args";
  
  $len = $len * 1;
  $columns .="INSERT INTO syscolumns\n" . 
    "(col_name,col_label,col_type,col_len, tbl_name, col_query, col_disp)\n" .
      "VALUES ('$column', '$caption', '$type', $len, '$table', $query, $disp)".
	"\n\\g\n";
  
  if ($keytype) {
    $keys .= "INSERT INTO syskeys\n" . 
      "   (col_name, tbl_name, key_type)\n" .
	"   VALUES ('$column', '$table', '$keytype')\n\\g\n";     
  }
  if ($link) {
    $links .= "INSERT INTO syslinks\n" . 
      "   (col_name_label, col_name_target, lnk_type)\n" .
	"   VALUES ('$lnklabel', '$column', '$link')\n\\g\n";     
  }
  
}
if ($def) {
  if ($catonly) {
    print $tables, $columns, $keys, $links;
  } else {
    print $drop,$head,$def,")\n\\g\n",$tables,$columns,$keys,$links;
  }
}




sub mkcatalog {

  print <<EOF;
DROP TABLE systables
\\g
CREATE TABLE systables (
   tbl_name        char (32) not null,
   tbl_description char (128),
   tbl_seehtml     char (64)
   )
\\g

DROP TABLE syscolumns
\\g
CREATE TABLE syscolumns (
   col_name  char (32) not null,
   col_label char (128),
   col_type  char (4),
   col_len  int,
   tbl_name  char (32),
   col_query int,
   col_disp int
   )
\\g

DROP TABLE syskeys
\\g
CREATE TABLE syskeys (
   col_name char(32) not null,
   tbl_name char(32) not null,
   key_type char(15) not null
   )
\\g
DROP TABLE syslinks
\\g
CREATE TABLE syslinks (
   col_name_label  char(32) not null,
   col_name_target char(32) not null,
   lnk_type char(10)
   )
\\g
EOF
;

}

package Msql::RDBMS;

=head1 NAME

B<Msql::RDBMS> - Relational Database Management System for Msql

=head1 SYNOPSIS

   use Msql::RDBMS;

   $rdbms = new Msql::RDBMS;
   $rdbms->show;

=head1 DESCRIPTION

This is a fully catalog driven database management system for Perl 5
and mini-SQL. You should use it in conjunction with the sqldef.pl
script, found in the utility/ subdirectory of the installation; this
script will generate data definition language for your tables.

=head1 GENERATING DATA DEFINITION LANGUAGE

You must pass the name of a schema definition file to sqldef.pl (an
example, B<schema.def>, is included in the examples/ subdirectory of
the distribution).  Example usage:

   sqldef.pl schema.def

The above example will send the data definition language to STDOUT. To
send it to mini-SQL (this will wipe out all of the data in the
specified database):

   sqldef.pl schema.def | msql database-name

The B<schema.def> file contains a little bit of documentation on
how the data is organized within the file, and how you can set 
up your own tables.

=head1 USAGE

You can call up the entire Relational Database Management System from
your browser with a URL like this:

   http://bozos.on.the.bus/sample.cgi?db=demo

Where B<sample.cgi> is a Perl script containing the three lines of
code shown in B<SYNOPSIS>.

=head1 DEBUGGING

You can get some debugging information, which consists of a CGI::dump,
and an SQL statement, if relevant, by including debug=1 in the URL.

=head1 TODO

  Generate forms for interactive data definition.
  Enforce referential integrity (cascade/block deletes).
* Add support for many-to-many relationships.
* Enforce uniqueness for label columns.
* Add fancy display options that support automagic hyperlinking of
     URLs and email addresses.

* denotes feature present in the original PHP/FI version.

=head1 AUTHOR

Brian Jepson <bjepson@conan.ids.net>

You may distribute this under the same terms as Perl itself.

=head1 SEE ALSO

CGI::CGI, CGI::Carp, Msql, File::Counterfile

=cut

require 5.002;
use CGI;
use CGI::Carp;
use Msql;
use File::CounterFile;

%tableAttributes = ( "DESCRIPTION" => 'tbl_description');
%comp_num = ("="        => "Equal To",
	     "&gt;"     => "Greater Than",
	     "&lt;"     => "Less Than",
	     "&lt;="    => "Less Than or Equal To",
	     "&gt;="    => "Greater Than or Equal To",
	     "&lt;&gt;" => "Not Equal To");
@comp_num = ("=", "&gt;", "&lt;", "&lt;=", "&gt;=", "&lt;&gt;");

%comp_char = ("LIKE"    => "Find Similar",
	      "="        => "Equal To",
	      "&lt;&gt;" => "Not Equal To");
@comp_char = ("LIKE", "=", "&lt;&gt;");

BEGIN {
  $header_printed = 1;
  $| =1;
  print "Content-type: text/html\n\n";
  use CGI::Carp qw(carpout);
  carpout(STDOUT);
}	


sub new {

  my ($class) = shift;
  my $self    = {};
  bless $self,$class;
  $self->initialize;

  $self;

}

sub show {

  my($self) = shift;
  my($query) = $self->{'query'};

  my($dumpdata) = $query->dump if $query->param('debug');

  if ($self->{'action'} eq "QUERY") {
    $self->tableInfo;
    $self->multiForm;
  } elsif ($self->{'action'} eq "GETQUERY") {
    $self->tableInfo;
    $self->getquery;
  } elsif ($self->{'action'} eq "NEW") {
    $self->tableInfo;
    $self->multiForm;
  } elsif ($self->{'action'} eq "EDIT") {
    $self->tableInfo;
    $self->multiForm;
  } elsif ($self->{'action'} eq "UPDATE") {
    $self->tableInfo;
    $self->update;
  } elsif ($self->{'action'} eq "INSERT") {
    $self->tableInfo;
    $self->insert;
  } elsif ($self->{'action'} eq "DELETE") {
    $self->tableInfo;
    $self->delete;
  } else {
    $self->showtables;
  }

  my $url = $query->script_name . "?db=" . $self->{'db'} .
            "&debug=" . $query->param('debug');
  print qq[<p><a href="$url">Return to main menu</a>];

  if ($query->param('debug')) {
    print "<p>CGI::dump:<p>";
    print $dumpdata;
  }
  print $query->end_html;

}

sub tableInfo {

  my($self) = shift;

  die "No table name was specified." unless $self->{'table'};

  # grab some metadata
  #
  $self->{'title'} = RDBMSGetTableAttribute(
		       $self->{'dbh'}, $self->{'table'}, "DESCRIPTION");
  $self->{'pkey'}  = RDBMSGetPrimaryKey($self->{'dbh'}, $self->{'table'});
  $self->{'label'} = RDBMSGetLabelKey($self->{'dbh'}, $self->{'table'});
  
  RDBMSGetColumnInfo($self->{'dbh'}, $self->{'table'},
		     \@columns, \%columns);

  @{$self->{'columns'}} = @columns;
  %{$self->{'column_info'}} = %columns;

}

sub showtables {

  my ($self) = shift;
  my (@fn, @row);
  my ($sth) = $self->{'dbh'}->Query("select tbl_name, tbl_description
                                     from systables");

  my ($query) = $self->{'query'};

  print "<table border>";
  @fn{@{$sth->name}} = 0..@{$sth->name}-1;
  while (@row = $sth->FetchRow()) {

    $query->param('table', $row[$fn{'tbl_name'}]);

    print "<tr>\n";
    print "<td>\n";

    $query->param('action', "QUERY");
    $url = $query->self_url;
    print qq[<a href="$url">
	     Query the $row[$fn{'tbl_description'}] table</a><br>];

    $query->param('action', "NEW");
    $url = $query->self_url;
    print qq[<a href="$url">
	     Add to the $row[$fn{'tbl_description'}] table</a><br>];

    print "</td>\n";
    print "</tr>\n";

  }
  print "</table>";

}

sub initialize {

  my($self) = shift;
  $self->{'query'} = new CGI;

  my $query = $self->{'query'}; # make things a little easier

  $self->{'table'}  = $query->param('table');
  $self->{'db'}     = $query->param('db');
  $self->{'action'} = $query->param('action');

  die "A database name must be specified" unless $self->{'db'};

  $self->{'dbh'} = Msql->Connect || die "Could not connect to mSQL!";
  $self->{'dbh'}->SelectDB($self->{'db'});

}

#
# this is a pretty polymorphic method which will handle
# add, edit, query forms
#
sub multiForm {

  my($self) = shift;
  my($query) = $self->{'query'};

  my ($i, $numrows, $urlaction, $submit, $pkeyfield, @row_edit);
  my ($ref_prompt, $filter, $expr, @fn_edit, $sth_edit);

  my @columns = @{$self->{'columns'}};
  my %columns = %{$self->{'column_info'}};

  print $query->header unless $header_printed;
  print $query->start_html(-title=>$ref_title);

  if ($self->{'action'} eq "NEW") {
    $ref_prompt  = "Add Entry";
    $i = -1;
    $numrows = 0;
    $query->param('action', "INSERT");
    $submit = "Add";
  } elsif ($self->{'action'} eq "QUERY") {
    $ref_prompt  = "Enter Query Parameters";
    $i = -1;
    $numrows = 0;
    $query->param('action', "GETQUERY");
    $submit = "Query";
  } elsif ($self->{'action'} eq "EDIT") {
    $ref_prompt = "Edit Old Entry";
    # if the primary key was passed in as a CGI variable,
    # then it means that this form was meant to only
    # bring up the row corresponding to that key.
    #
    my($pkeyval) = $query->param($self->{'pkey'});
    if ($pkeyval) {
      $filter = " where $self->{'pkey'} = $pkeyval ";
    }
    $sth_edit = $self->{'dbh'}->Query(
			   "select * from $self->{'table'} $filter");
    @fn_edit{@{$sth_edit->name}} = 0..@{$sth_edit->name}-1;
    $numrows = $sth_edit->numrows;
    $query->param('action', "UPDATE");
    $submit = "Change";
  }

  print "<table border>";
  for ($i; $i < $numrows; $i++) {

    if ($i >= 0) {
      @row_edit = $sth_edit->FetchRow();
    }
  
    print "<tr><td>";
    print "<strong>$ref_prompt</strong>:\n";
    print "<pre>";
  
    # start the form
    print $query->startform(-method=>'POST',
			    -action=>$query->script_name);
    print $query->hidden("debug");
    print $query->hidden("table");
    print $query->hidden("action");
    print $query->hidden("db");

    foreach (@columns) {

      my ($col_value, $comparisons);
      my ($col_name)  = $columns{$_}{'col_name'};
      my ($col_label) = $columns{$_}{'col_label'};
      my ($col_type)  = $columns{$_}{'col_type'};
      my ($col_query) = $columns{$_}{'col_query'};
      my ($col_len)   = $columns{$_}{'col_len'};
      $col_len = 10 unless $col_len;
    
      if ($col_query > 0 || $self->{'action'} ne "QUERY") {
	
	if ($i == -1) {
	  if ($col_type eq "char") {
	    $col_value = "";
	    $comparisons = $query->popup_menu(-name=>"$col_name" . "_compare",
					      -values=>\@comp_char,
					      -labels=>\%comp_char);
	  } elsif ($col_type eq "int") {
	    $col_value = 0;
	    $comparisons = $query->popup_menu(-name=>"$col_name" . "_compare",
					      -values=>\@comp_num,
					      -labels=>\%comp_num);
					    
	  } elsif ($col_type eq "real") {
	    $col_value = 0.0;
	    $comparisons = $comp_num;
	  } elsif ($col_type eq "money") {
	    $col_value = 0.0;
	    $comparisons = $comp_num;
	  }
	} else {
	  $col_value = $row_edit[$fn_edit{$col_name}];
	}
	if ($col_type eq 'real' || $col_type eq 'money') {
	  $col_value *= 1;
	}
      
	# print a hidden field for the primary key.
	if ($col_name eq $self->{'pkey'}) {
	  $pkeyfield =  $query->hidden($col_name, $col_value);
	  print $pkeyfield;
	} else {
	  
	  # but for other types, print out the label with
	  # some padding...
	  print $col_label . (" " x (20 - length($col_label)));
	  
	  # if it's a foreign key reference, some special handling
	  # is required.
	  #
	  if (RDBMSGetKeyType($self->{'dbh'}, $self->{'table'}, $col_name) 
	      eq "FOREIGN") {
	    
	    # find the name of the table which has this column
	    # (the foreign key from the current table) as its
	    # primary key
	    #
	    my ($ref_fkeytable) = 
	      RDBMSGetTableOfPrimaryKey($self->{'dbh'}, $col_name);
	    
	    # find out what the "label key" of that table is
	    #
	    my ($ref_fkeylabel) = 
	      RDBMSGetLabelKey($self->{'dbh'}, $ref_fkeytable);
	    
	    # grab all of the rows from that table
	    #
	    my ($sth) = $self->{'dbh'}->Query("select $col_name, $ref_fkeylabel
                               from $ref_fkeytable");

	    my ($ml) = 0;

	    my (%menu_labels, @menu_options, @fn, @row);
	    # if the screen is in query-mode, then make
	    # sure to add a "none" option...
	    #
	    if ($self->{'action'} eq "QUERY") {
	      $menu_labels{"0"} = "[ None ]";
	      $menu_options[$ml++] = "0";
	    }
	    
	    # do the usual voodoo to process each row in the
	    # result set. Make two arrays; one (scalar) of only the
	    # option values, and a hash of the option values (the
	    # foreign key value) and the option labels.
	    #
	    @fn{@{$sth->name}} = 0..@{$sth->name}-1;
	    while (@row = $sth->FetchRow()) {
	      $menu_labels{$row[$fn{$col_name}]} = $row[$fn{$ref_fkeylabel}];
	      $menu_options[$ml++] = $row[$fn{$col_name}];
	    }

	    # throw it up there as a popup menu
	    #
	    print $query->popup_menu(-name=>$col_name, 
				     -values=>\@menu_options,
				     -labels=>\%menu_labels,
				     -default=>$col_value)
	  } else {
	    
	    if ($self->{'action'} eq "QUERY") {
	      chop($comparisons);
	      print $comparisons;
	    }

	    # if it's a normal old field, just put up a 
	    # regular old text field (or textarea, if it's
	    # a big field)
	    #
	    if ($col_len < 65) {
	      print $query->textfield(-name=>$col_name,
				      -default=>$col_value,
				      -size=>$col_len, 
				      -maxlength=>$col_len);
	    } else {
	      print $query->textarea(-name=>$col_name,
				     -default=>$col_value,
				     -rows=>5, 
				     -cols=>45);
	    }
	  }
	  print "\n";	
	}
      }
    }
    
    print $query->submit(-name=>"submit",
			 -value=>$submit);
    print $query->endform;
    
    if ($self->{'action'} eq "EDIT") {

      $query->param('action', "DELETE");

      print $query->startform(-method=>'POST',
			      -action=>$query->script_name);

      print $query->hidden("debug");
      print $query->hidden("table");
      print $query->hidden("db");
      print $query->hidden("action");

      print $pkeyfield;

      print $query->submit(-name=>"submit",
			   -value=>"Delete");
      print $query->endform;
    }
    
    print "</td></tr>";
    
  }
  print "</table>";
  

}

#
# perform a query that was defined in multiForm
#
sub getquery {

  my ($self) = shift;
  my ($query) = $self->{'query'};
  my @columns = @{$self->{'columns'}};
  my %columns = %{$self->{'column_info'}};
  my ($comparison, $value, $sql);

  print $query->header unless $header_printed;
  print $query->start_html(-title=>$self->{'title'});

  print "<h1>Choose from the list of $self->{'title'}</h1>";

  foreach (@columns) {

    $comparison = $query->param($_ . '_compare');
    $comparison = '=' unless $comparison;
    $value      = $query->param($_);

    $query->delete($_ . '_compare');
    $query->delete($_);
    # wrap char types in a single quote.
    if ($columns{$_}{'col_type'} eq 'char' && $value) {
      if ($comparison eq "LIKE") {
	($value = "'%$value%'") =~ s/([a-z]|[A-Z])/\[\l$1\u$1\]/g;
      } else {
	$value = "'$value'";
      }
    }
    
    if ($value) {
      $sql .= " AND " if $seen; $seen = 1;
      $sql .= " $_ $comparison $value ";
    }
    
  }
  
  if ($sql) {

    $sql = "SELECT $self->{'pkey'}, $self->{'label'} 
            FROM $self->{'table'} WHERE " . $sql;
    print "<p>$sql<p>" if $query->param('debug');
    my($sth, @fn, @row, $count, $url, $this_label);

    $query->delete('submit');
    $query->param('action', "EDIT");

    $sth = $self->{'dbh'}->Query($sql);
    @fn{@{$sth->name}} = 0..@{$sth->name}-1;
    while (@row = $sth->FetchRow()) {

      $count++;
      $query->param($self->{'pkey'}, $row[$fn{$self->{'pkey'}}]);

      $this_label = $row[$fn{$self->{'label'}}];
      $url = $query->self_url;
      print qq[<a href="$url">$this_label</a><br>];
    }
    print "No rows matched your query." unless $count;

  } else {
    print "You entered no parameters for the query!";
  }

}

sub update {

  my ($self) = shift;
  my ($query) = $self->{'query'};
  my ($seen, $value, $column_list, $sql);

  print $query->header unless $header_printed;
  print $query->start_html(-title=>$self->{'title'});

  my @columns = @{$self->{'columns'}};
  my %columns = %{$self->{'column_info'}};

  foreach (@columns) {

    if ($_ ne $self->{'pkey'}) {

      $value = $query->param($_);
      # wrap char types in a single quote.
      if ($columns{$_}{'col_type'} eq 'char') {
	$value = "'$value'";
      }

      if ($columns{$_}{'col_type'} eq 'real' 
	  || $columns{$_}{'col_type'} eq 'money') {
	$value *= 1;
      }

      $column_list .= ", " if $seen;
      $column_list .= "$_ = $value";
      $seen = 1;
    }

  }

  my ($this_pkey, $sql, $sth);
  $this_pkey = $query->param($self->{'pkey'});
  $sql = "UPDATE $self->{'table'}
          SET $column_list WHERE $self->{'pkey'} = $this_pkey";

  print "<p>$sql<p>" if $query->param('debug');
  if ($sth = $self->{'dbh'}->Query($sql)) {
    print "The data was changed successfully.";
  } else {
    print "The action was unsuccessful.";
  }

}

sub insert {

  my ($self) = shift;
  my ($query) = $self->{'query'};
  my ($seen, $value, $column_list, $insert_list, $sql);

  print $query->header unless $header_printed;
  print $query->start_html(-title=>$self->{'title'});

  my @columns = @{$self->{'columns'}};
  my %columns = %{$self->{'column_info'}};

  my($c)  = new File::CounterFile $self->{'table'};
  my($id) = $c->inc;

  foreach (@columns) {

    $column_list .= ", " if $seen;
    $column_list .= $_;

    $value = $query->param($_);
    if ($_ eq $self->{'pkey'}) {
      $value = $id;
    }

    # wrap char types in a single quote.
    if ($columns{$_}{'col_type'} eq 'char') {
      $value = "'$value'";
    }

    if ($columns{$_}{'col_type'} eq 'real' 
	|| $columns{$_}{'col_type'} eq 'money') {
      $value *= 1;
    }
    $insert_list .= ", " if $seen;
    $insert_list .= $value;
    
    $seen = 1;
  }

  $sql = "INSERT INTO $self->{'table'} ( $column_list ) 
	VALUES ( $insert_list )";

  print "<p>$sql<p>" if $query->param('debug');
  if ($sth = $self->{'dbh'}->Query($sql)) {
    print "The new data was added successfully.";
  } else {
    print "The action was unsuccessful.";
  }

}

sub delete {

  my ($self) = shift;
  my ($query) = $self->{'query'};

  print $query->header unless $header_printed;
  print $query->start_html(-title=>$self->{'title'});

  my ($this_pkey, $sql, $sth);
  $this_pkey = $query->param($self->{'pkey'});
  $sql = "DELETE FROM $self->{'table'}
          WHERE $self->{'pkey'} = $this_pkey"; 
  print "<p>$sql<p>" if $query->param('debug');
  if ($sth = $self->{'dbh'}->Query($sql)) {
    print "The row was deleted successfully.";
  } else {
    print "The action was unsuccessful.";
  }

}

#
# semi-static methods
#

sub RDBMSGetTableAttribute {

  my $dbh   = shift;
  my $table = shift;
  my $attrib = $tableAttributes{shift};
  my @row, @fn, $col, $sth;

  $sth = $dbh->Query ("select * from systables 
                     where tbl_name = '$table'") || die;
  die "Could not locate specified table." unless @row = $sth->FetchRow();

  @fn{@{$sth->name}} = 0..@{$sth->name}-1;
  $row[$fn{'tbl_description'}];

}

sub RDBMSGetColumnInfo {

  my $dbh   = shift;
  my $table = shift;
  my $columns_array = shift;
  my $columns_hash  = shift;
  my @row, @fn, $col, $sth_columns;

  $sth_columns = $dbh->Query("select * from syscolumns 
                            where tbl_name = '$table'");
  @fn{@{$sth_columns->name}} = 0..@{$sth_columns->name}-1;

  while (@row = $sth_columns->FetchRow()) {
    $$columns_array[$col++] = $row[$fn{'col_name'}];
    foreach (@{$sth_columns->name}){
      $$columns_hash{$row[$fn{'col_name'}]}{$_} = $row[$fn{$_}];
    }
  }

}

sub RDBMSGetKey {
  my $dbh   = shift;
  my $table = shift;
  my $key   = shift;
  my $sth, @fn, @row;

  $sth = $dbh->Query ("select col_name from syskeys
                          where tbl_name = '$table' 
                          and key_type = '$key'");

  @fn{@{$sth->name}} = 0..@{$sth->name}-1;
  return undef unless (@row = $sth->FetchRow());

  $row[$fn{'col_name'}];

}

sub RDBMSGetLabelKey {
   RDBMSGetKey(shift, shift, "LABEL");
}

sub RDBMSGetPrimaryKey {
   RDBMSGetKey(shift, shift, "PRIMARY");
}

sub RDBMSGetKeyType {
  my $dbh    = shift;
  my $table  = shift;
  my $column = shift;
  my $sth, @fn, @row;

  $sth = $dbh->Query ("select key_type from syskeys
                          where tbl_name = '$table' 
                          and   col_name = '$column'");

  @fn{@{$sth->name}} = 0..@{$sth->name}-1;
  return undef unless (@row = $sth->FetchRow());

  $row[$fn{'key_type'}];

}

sub RDBMSGetTableOfKey {
  my $dbh    = shift;
  my $column = shift;
  my $key    = shift;
  my $sth, @fn, @row;

  $sth = $dbh->Query ("select tbl_name from syskeys
                          where col_name = '$column' 
                          and key_type = '$key'");

  @fn{@{$sth->name}} = 0..@{$sth->name}-1;
  return undef unless (@row = $sth->FetchRow());

  $row[$fn{'tbl_name'}];

}

sub RDBMSGetTableOfPrimaryKey {
  RDBMSGetTableOfKey(shift, shift, "PRIMARY");
}


1;



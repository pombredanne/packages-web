package Packages::DB;

use strict;
use warnings;

use Exporter;
use DB_File;
use Packages::CGI;
use Packages::Config qw( $TOPDIR $DBDIR );

our @ISA = qw( Exporter );
our ( %packages, %sources, %src2bin, %did2pkg, %descriptions,
      %postf, %spostf, %debtags, %desctrans,
      $obj, $s_obj, $p_obj, $sp_obj );
our @EXPORT = qw( %packages %sources %src2bin %did2pkg %descriptions
		  %postf %spostf %debtags %desctrans
		  $obj $s_obj $p_obj $sp_obj );
our $db_read_time ||= 0;

sub init {
    my $dbmodtime = (stat("$DBDIR/packages_small.db"))[9] || 0;
    if ($dbmodtime > $db_read_time) {
	undef $obj;
	untie %packages;
	$obj = tie %packages, 'DB_File', "$DBDIR/packages_small.db",
	O_RDONLY, 0666, $DB_BTREE
	    or die "couldn't tie DB $DBDIR/packages_small.db: $!";
	undef $s_obj;
	untie %sources;
	$s_obj = tie %sources, 'DB_File', "$DBDIR/sources_small.db",
	O_RDONLY, 0666, $DB_BTREE
	    or die "couldn't tie DB $DBDIR/sources_small.db: $!";
	untie %src2bin;
	tie %src2bin, 'DB_File', "$DBDIR/sources_packages.db",
	O_RDONLY, 0666, $DB_BTREE
	    or die "couldn't open $DBDIR/sources_packages.db: $!";
	untie %descriptions;
	tie %descriptions, 'DB_File', "$DBDIR/descriptions.db",
	O_RDONLY, 0666, $DB_BTREE
	    or die "couldn't tie DB $DBDIR/descriptions.db: $!";
	untie %desctrans;
	tie %desctrans, 'DB_File', "$DBDIR/descriptions_translated.db",
	O_RDONLY, 0666, $DB_BTREE
	    or die "couldn't tie DB $DBDIR/descriptions_translated.db: $!";
	untie %did2pkg;
	tie %did2pkg, 'DB_File', "$DBDIR/descriptions_packages.db",
	O_RDONLY, 0666, $DB_BTREE
	    or die "couldn't tie DB $DBDIR/descriptions_packages.db: $!";
	untie %debtags;
# Currently disabled, does not work
#	tie %debtags, 'DB_File', "$TOPDIR/files/debtags/vocabulary.db",
#	O_RDONLY, 0666, $DB_BTREE
#	    or die "couldn't tie DB $TOPDIR/files/debtags/vocabulary.db: $!";
	undef $p_obj;
	untie %postf;
	$p_obj = tie %postf, 'DB_File', "$DBDIR/package_postfixes.db",
	O_RDONLY, 0666, $DB_BTREE
	    or die "couldn't tie postfix db $DBDIR/package_postfixes.db: $!";
	undef $sp_obj;
	untie %spostf;
	$sp_obj = tie %spostf, 'DB_File', "$DBDIR/source_postfixes.db",
	O_RDONLY, 0666, $DB_BTREE
	    or die "couldn't tie postfix db $DBDIR/source_postfixes.db: $!";

	debug( "tied databases ($dbmodtime > $db_read_time)" ) if DEBUG;
	$db_read_time = $dbmodtime;
    }
}

1;


package Packages::Page;

use strict;
use warnings;

use Data::Dumper;
use Exporter;
use Deb::Versions;
use Packages::CGI;
use Packages::I18N::Locale;

our @ISA = qw( Exporter );
our @EXPORT_OK = qw( split_name_mail parse_deps );
our %EXPORT_TAGS = ( all => [ @EXPORT_OK ] );

our $ARCHIVE_DEFAULT = '';
our $SECTION_DEFAULT = 'main';
our $SUBSECTION_DEFAULT = 'unknown';
our $PRIORITY_DEFAULT = 'unknown';
our $ESSENTIAL_DEFAULT = 'no';
our $MAINTAINER_DEFAULT = 'unknown <unknown@email.invalid>';

sub new {
    my $classname = shift;
    my $name = shift || '';
    my $config = shift || {};

    my $self = {};
    bless( $self, $classname );

    $self->{package} = $name;
    $self->{config} = $config;

    return $self;
}

sub split_name_mail {
    my $string = shift;
    my ( $name, $email );
    if ($string =~ /(.*?)\s*<(.*)>/o) {
        $name =  $1;
        $email = $2;
    } elsif ($string =~ /^[\w.-]*@[\w.-]*$/o) {
        $name =  $string;
        $email = $string;
    } else {
        $name = N_( 'package has bad maintainer field' );
        $email = '';
    }
    $name =~ s/\s+$//o;
    return ($name, $email);
}

sub override_maint {
    my ($self, $data) = @_;

    return if $data->{'original-maintainer'};
    return unless $data->{maintainer};

    my ($name, $mail) = split_name_mail( $data->{maintainer} );

    # taken from etc/pkgbinarymangler/maintainermangler.overrides
    return if $mail =~ /\@(tanglu\.org|lists\.tanglu\.org)^/o;

    $data->{'original-maintainer'} = $data->{maintainer};
    $data->{maintainer} = 'Tanglu Developers <tanglu-devel-discuss@lists.tanglu.org>';

    return 1;
}

sub handle_maintainer_fields {
    my ($self, $data) = @_;
    my (@uploaders, @orig_uploaders);

    if ($data->{'original-maintainer'}) {
	push @orig_uploaders, [ split_name_mail( $data->{'original-maintainer'} ) ];

	$data->{uploaders} ||= '';
	my @up_tmp = split( /\s*,\s*/,
			    $data->{uploaders} );
	foreach my $up (@up_tmp) {
		push @orig_uploaders, [ split_name_mail( $up ) ];
	}
	if ($data->{maintainer} ||= '') {
	    push @uploaders, [ split_name_mail( $data->{maintainer} ) ];
	}
    } else {
	if ($data->{maintainer} ||= '') {
	    if ($self->override_maint($data)) {
		return $self->handle_maintainer_fields($data);
	    }

	    push @uploaders, [ split_name_mail( $data->{maintainer} ) ];
	}
	if ($data->{uploaders}) {
	    my @up_tmp = split( /\s*,\s*/,
				$data->{uploaders} );
	    foreach my $up (@up_tmp) {
		if ($up ne $data->{maintainer}) { # weed out duplicates
		    push @uploaders, [ split_name_mail( $up ) ];
		}
	    }
	}
    }

    return (\@uploaders, \@orig_uploaders);
}

sub add_src_data {
    my ($self, $src, $data) = @_;

    my %data = split /\00/o, $data;

    $self->{src}{package} = $src;
    $self->{src}{version} = $data{version};
    if ($data{files}) {
	my @files = split /\01/so, $data{files};
	$self->{src}{files} = \@files;
    }
    $self->{src}{directory} = $data{directory};
    my ($uploaders, $orig_uploaders) = $self->handle_maintainer_fields(\%data);
    $self->{src}{uploaders} = $uploaders;
    $self->{src}{orig_uploaders} = $orig_uploaders if @$orig_uploaders;

    return 1;
}

sub add_provided_by {
    my ($self, $provided_by) = @_;

    $self->{provided_by} ||= [];
    push @{$self->{provided_by}}, @$provided_by;
}

sub is_virtual {
    my ($self) = @_;

    return (exists($self->{provided_by}) && !exists($self->{versions}));
}

our @TAKE_NEWEST = qw( description description-md5 essential priority section subsection tag
		       archive source source-version homepage maintainer original-maintainer uploaders);
our @STORE_ALL = qw( version source source-version installed-size size
		     filename md5sum sha1 sha256 task
		     origin bugs suite archive section );
our @DEP_FIELDS = qw( depends pre-depends recommends suggests enhances
		      provides conflicts );
sub merge_package {
    my ($self, $data) = @_;

    ($data->{package} && $data->{version} && $data->{architecture}) || return;
    $self->{package} ||= $data->{package};
    ($self->{package} eq $data->{package}) || return;
    debug( "merge package $data->{package}/$data->{version}/$data->{architecture} into $self (".($self->{newest}||'').")", 2 ) if DEBUG;

    (my $version = $data->{version}) =~ s/\+b\d+$//o; # strip binNMU number
    unless ($self->{newest}) {
	debug( "package $data->{package}/$data->{version}/$data->{architecture} is first to merge", 3 ) if DEBUG;
	foreach my $key (@TAKE_NEWEST) {
	    $self->{data}{$key} = $data->{$key};
	}
	foreach my $key (@STORE_ALL) {
	    $self->{versions}{$data->{architecture}}{$key}
	    = $data->{$key};
	}
	foreach my $key (@DEP_FIELDS) {
	    $self->normalize_dependencies($key, $data);
	}
	$self->{newest} = $version;

        return 1;
    }

    debug( "package $data->{package}/$data->{version}/$data->{architecture} is subsequent merge", 3 ) if DEBUG;
    my $is_newest;
    my $cmp = version_cmp( $version, $self->{newest} );
    # packages from the central archive are preferred over all
    # others with the same version number but from other archives
    if ($is_newest = ($cmp > 0)
	|| (!$cmp && ($data->{archive} eq 'us') && ($self->{data}{archive} ne 'us'))) {
	$self->{newest} = $version;
	foreach my $key (@TAKE_NEWEST) {
	    $self->{data}{$key} = $data->{$key};
	}
    }
    debug( "is_newest= ".($is_newest||0), 3 ) if DEBUG;
    if (!$self->{versions}{$data->{architecture}}
	|| $is_newest
	|| (version_cmp( $data->{version},
			 $self->{versions}{$data->{architecture}}{version} ) > 0)) {
	foreach my $key (@STORE_ALL) {
	    $self->{versions}{$data->{architecture}}{$key}
	    = $data->{$key};
	}
	foreach my $key (@DEP_FIELDS) {
	    $self->normalize_dependencies($key, $data);
	}
    }

    return 1;
}

sub normalize_dependencies {
    my ($self, $dep_field, $data) = @_;

    my ($deps_norm, $deps) = parse_deps( $data->{$dep_field}||'' );
    $self->{dep_fields}{$data->{architecture}}{$dep_field} =
	[ $deps_norm, $deps ];
}

sub parse_deps {
    my ($dep_str) = @_;

    my (@dep_and_norm, @dep_and);
    foreach my $dep_and (split( /\s*,\s*/m, $dep_str )) {
	next if $dep_and =~ /^\s*$/;
	my (@dep_or_norm, @dep_or);
	foreach my $dep_or (split( /\s*\|\s*/m, $dep_and )) {
            my ($pkg, $relation, $version, @arches) = ('','','');
            $pkg = $1 if $dep_or =~ s/^([a-zA-Z0-9][a-zA-Z0-9+._-]*)\s*//m;
            ($relation, $version) = ($1, $2)
		if $dep_or =~ s/^\(\s*(=|<=|>=|<<?|>>?)\s*([^\)]+).*\)\s*//m;
	    @arches = split(/\s+/m, $1) if $dep_or =~ s/^\[([^\]]+)\]\s*//m;
	    push @dep_or_norm, "$pkg($relation$version)[".
		join(" ",sort(@arches))."]";
	    push @dep_or, [ $pkg, $relation, $version, \@arches ];
	}
	push @dep_and_norm, join('|',@dep_or_norm);
	push @dep_and, \@dep_or;
    }
    return (\@dep_and_norm, \@dep_and);
}

sub get_newest {
    my ($self, $field) = @_;

    return $self->{data}{$field};
}
sub get_src {
    my ($self, $field) = @_;

    return $self->{src}{$field};
}

sub get_architectures {
    my ($self) = @_;

    return keys %{$self->{versions}};
}

sub get_arch_field {
    my ($self, $field) = @_;

    my %result;
    foreach (sort keys %{$self->{versions}}) {
	$result{$_} = $self->{versions}{$_}{$field}
	if $self->{versions}{$_}{$field};
    }

    return \%result;
}

sub get_versions {
    my ($self) = @_;

    my %versions;
    foreach (keys %{$self->{versions}}) {
	my $version = $self->{versions}{$_}{version};
	$versions{$version} ||= [];
	push @{$versions{$version}}, $_;
    }

    return \%versions;
}

sub get_version_string {
    my ($self) = @_;

    my $versions = $self->get_versions;
    my @versions = version_sort keys %$versions;
    my (@v_str, $v_str, $v_str_arch);
    if ( scalar @versions == 1 ) {
	@v_str = ( [ $versions[0], undef ] );
	$v_str = $versions[0];
	$v_str_arch = $versions[0];
    } else {
	my @v_str_arch;
	foreach ( @versions ) {
	    push @v_str, [ $_, $versions->{$_} ];
	    push @v_str_arch, "$_ [".join(', ', sort @{$versions->{$_}})."]";
	}
	$v_str_arch = join( ", ", @v_str_arch );
	$v_str = join( ", ",  @versions );
    }

    return ($v_str, $v_str_arch, \@v_str);
}

sub get_dep_field {
    my ($self, $dep_field) = @_;

    my @architectures = $self->get_architectures;

    my ( %dep_pkgs, %arch_deps );
    foreach my $a ( @architectures ) {
	next unless exists $self->{dep_fields}{$a}{$dep_field};
	my ($a_deps_norm, $a_deps) = @{$self->{dep_fields}{$a}{$dep_field}};
#	debug( "get_dep_field: $dep_field/$a: ".Dumper($a_deps_norm,$a_deps), 3 ) if DEBUG;
	for ( my $i=0; $i < @$a_deps; $i++ ) { # splitted by ,
	    $dep_pkgs{$a_deps_norm->[$i]} = $a_deps->[$i];
	    $arch_deps{$a}{$a_deps_norm->[$i]}++;
	}
    }
    @architectures = sort keys %arch_deps;
 #   debug( "get_dep_field called:\n ".Dumper( \%dep_pkgs, \%arch_deps ), 3 ) if DEBUG;

    my @deps;
    if ( %dep_pkgs ) {
	my $old_pkgs = '';
	my $is_old_pkgs = 0;
	foreach my $dp ( sort keys %dep_pkgs ) {
	    my @dp_alts = @{$dep_pkgs{$dp}};
	    my ( @pkgs, $pkgs );
	    foreach (@dp_alts) { push @pkgs, $_->[0]; }
	    $pkgs = "@pkgs";

	    unless ( $is_old_pkgs = ($pkgs eq $old_pkgs) ) {
		$old_pkgs = $pkgs;
	    }

	    my ($arch_neg, $arch_str) = _compute_arch_str ( $dp, \%arch_deps,
							    \@architectures );

	    my @res_pkgs; my $pkg_ix = 0;
	    foreach my $p_name ( @pkgs ) {
		if ( $pkg_ix > 0 ) { $arch_str = ""; }

		my $pkg_version = "";
		$pkg_version = "$dep_pkgs{$dp}[$pkg_ix][1] $dep_pkgs{$dp}[$pkg_ix][2]"
		    if $dep_pkgs{$dp}[$pkg_ix][1];


		push @res_pkgs, [ $p_name, $pkg_version, $arch_neg,
				  $arch_str ];
		$pkg_ix++;
	    }
	    push @deps, [ $is_old_pkgs, @res_pkgs ];
	}
    }
    return \@deps;
}

sub _compute_arch_str {
    my ( $dp, $arch_deps, $all_archs, $is_src_dep ) = @_;

    my ( @dependend_archs, @not_dependend_archs );
    my $arch_str;
    foreach my $a ( @$all_archs ) {
	if ( exists $arch_deps->{$a}{$dp} ) {
	    push @dependend_archs, $a;
	} else {
	    push @not_dependend_archs, $a;
	}
    }
    my $arch_neg = 0;
    if ( @dependend_archs == @$all_archs ) {
	$arch_str = "";
    } else {
	if ( @dependend_archs > (@$all_archs/2) ) {
	    $arch_neg = 1;
	    $arch_str = join( ", ", @not_dependend_archs);
	} else {
	    $arch_str = join( ", ", @dependend_archs);
	}
    }
    return my @ret = ( $arch_neg, $arch_str );
}

1;

package Packages::CGI;

use Exporter;
our @ISA = qw( Exporter );
our @EXPORT = qw( fatal_error error hint debug msg
		  print_errors print_hints print_debug print_msgs );

our $debug = 0;

our (@fatal_errors, @errors, @debug, @msgs, @hints);

sub reset {
    @fatal_errors = @errors = @debug = @msgs = @hints = ();
}

sub fatal_error {
    push @fatal_errors, $_[0];
}
sub error {
    push @errors, $_[0];
}
sub hint {
    push @hints, $_[0];
}
sub debug {
    my $lvl = $_[1] || 0;
    push(@debug, $_[0]) if $debug > $lvl;
}
sub msg {
    push @msgs, $_[0];
}
sub print_errors {
    return unless @fatal_errors || @errors;
    print '<div style="background-color:#F99;font-weight:bold;padding:0.5em;margin:0;">';
    foreach ((@fatal_errors, @errors)) {
	print "<p>ERROR: $_</p>";
    }
    print '</div>';
}
sub print_debug {
    return unless $debug && @debug;
    print '<div style="font-size:80%;border:solid thin grey">';
    print '<h2>Debugging:</h2><pre>';
    foreach (@debug) {
	print "$_\n";
    }
    print '</pre></div>';

}
sub print_hints {
    return unless @hints;
    print '<div>';
    foreach (@hints) {
	print "<p style=\"background-color:#FF9;padding:0.5em;margin:0\">$_</p>";
    }
    print '</div>';
}
sub print_msgs {
    foreach (@msgs) {
	print "<p>$_</p>";
    }
}

1;

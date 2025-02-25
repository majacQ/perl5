#!./perl -w

# Verify that all files generated by perl scripts are up to date.

BEGIN {
    @INC = '..' if -f '../TestInit.pm';
}
use TestInit qw(T A); # T is chdir to the top level, A makes paths absolute
use strict;

require './regen/regen_lib.pl';
require './t/test.pl';
$::NO_ENDING = $::NO_ENDING = 1;

if ( $^O eq "VMS" ) {
  skip_all( "- regen.pl needs porting." );
}
if ($^O eq 'dec_osf') {
    skip_all("$^O cannot handle this test");
}
if ( $::IS_EBCDIC || $::IS_EBCDIC) {
  skip_all( "- We don't regen on EBCDIC." );
}
use Config;
if ( $Config{usecrosscompile} ) {
  skip_all( "Not all files are available during cross-compilation" );
}

my $tests = 25; # I can't see a clean way to calculate this automatically.

my %skip = ("regen_perly.pl"    => [qw(perly.act perly.h perly.tab)],
            "regen/keywords.pl" => [qw(keywords.c keywords.h)],
            "regen/uconfig_h.h" => [qw(uconfig.h)],
            "regen/mk_invlists.pl" => [qw(charclass_invlists.h uni_keywords.h)],
            "regen/regcharclass.pl" => [qw(regcharclass.h)],
           );

my %other_requirement = (
    "regen_perly.pl"        => "requires bison",
    "regen/keywords.pl"     => "requires Devel::Tokenizer::C",
    "regen/mk_invlists.pl"  => "needs the Perl you've just built",
    "regen/regcharclass.pl" => "needs the Perl you've just built",
);

my %skippable_script_for_target;
for my $script (keys %other_requirement) {
    $skippable_script_for_target{$_} = $script
        for @{ $skip{$script} };
}

my @files = map {@$_} sort values %skip;

open my $fh, '<', 'regen.pl'
    or die "Can't open regen.pl: $!";

while (<$fh>) {
    last if /^__END__/;
}
die "Can't find __END__ in regen.pl"
    if eof $fh;

foreach (qw(embed_lib.pl regen_lib.pl uconfig_h.pl
            regcharclass_multi_char_folds.pl
            charset_translations.pl
            mph.pl sorted_types.pl
            ),
         map {chomp $_; $_} <$fh>) {
    ++$skip{"regen/$_"};
}

close $fh
    or die "Can't close regen.pl: $!";

my @progs = grep {!$skip{$_}} <regen/*.pl>;
push @progs, 'regen.pl', map {"Porting/makemeta $_"} qw(-j -y);

plan (tests => $tests + @files + @progs);

OUTER: foreach my $file (@files) {
    open my $fh, '<', $file or die "Can't open $file: $!";
    1 while defined($_ = <$fh>) and !/Generated from:/;
    if (eof $fh) {
	fail("Can't find 'Generated from' line in $file");
	next;
    }
    my @bad;
    while (<$fh>) {
	last if /ex: set ro:/;
	unless (/^(?: \* | #)([0-9a-f]+) (\S+)$/) {
	    chomp $_;
	    fail("Bad line in $file: '$_'");
	    next OUTER;
	}

	my $digest = digest($2);
	note("$digest $2");
	push @bad, $2 unless $digest eq $1;
    }
    is("@bad", '', "generated $file is up to date");
    if (@bad && (my $skippable_script = $skippable_script_for_target{$file})) {
        my $reason = delete $other_requirement{$skippable_script};
        diag("Note: $skippable_script must be run manually, because it $reason")
            if $reason;
    }
}

foreach (@progs) {
    my $args = qq[-Ilib $_ --tap];
    note("./perl $args");
    my $command = "$^X $args";
    system $command
        and die <<~"HINT";
    Hint:  A failure in this file can often be corrected by running:
     ./perl -Ilib $_
HINT
}

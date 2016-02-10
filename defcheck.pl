#!/usr/bin/env perl

use strict;
use warnings;
use File::Find;
use IO::File;
use Path::Class::File;
use Data::Dumper;
use Cwd;
use Getopt::Std;
use vars qw/*name *dir *prune/;
*name = *File::Find::name;

sub usage {
	die <<__USAGE__;
defcheck.pl [options] <netbsd-src-top>
	-v	verbose
	-D	debug output
__USAGE__
}

my %opts;
getopts('Dv', \%opts) or usage();
usage() if ($#ARGV != 0);

my $srctop = shift;
chdir $srctop or die "chdir: $srctop: $!\n";

print "# ", scalar(localtime), "\n";
print "#\n";
print "# commandline: ", join(" ", $0, @ARGV), "\n";
print "#\n";

push(my @INCLUDE, ".", getcwd(), getcwd() . "/sys" );
my $FIND_FILES_DIR = "sys";
my $FIND_SOURCE_DIR = "sys";
my $SOURCE_PATTERN = qr/\.c$/;

my %include_nest_check;
my $files_db;

#
# find "files.xxx" in $SYSDIR, and parse
#
File::Find::find( {wanted =>
	sub {
		if ((m/^files\./) && (-f $_)) {
			my $defs = parse_defs(read_config($_));

			if (defined($defs)) {
				$files_db->{$name} = $defs;
			}
		}
	}
}, $FIND_FILES_DIR);

#
# build grep list
#
my $sym2files;
my $grep_list;
for my $files (keys(%$files_db)) {
	for my $include (keys(%{$files_db->{$files}})) {
		my @syms = @{$files_db->{$files}->{$include}};

		for (@syms) {
			$grep_list->{$_} = $include;
			$sym2files->{$_} = $files;
		}
	}
}


#
# checking inconsistency of include.
# when a source reference SYMBOL, the source must be include "opt_symbol.h"
#
File::Find::find( {wanted =>
	sub {
		if ((m/$SOURCE_PATTERN/) && (-f $_)) {
			define_check($name, $_, $grep_list);
		}
	}
}, $FIND_SOURCE_DIR);

sub define_check {
	my $label = shift;
	my $path = shift;
	my $greplist = shift;

#print STDERR "label=$label\n";
#print STDERR "path=$path\n";
#print STDERR Dumper($greplist);


	print STDERR "checking $label             \r" if ($opts{v});
	my $fh = new IO::File $path, "r";
	my @lines = <$fh>;
	$fh->close();

	my $body = join("", @lines);

	while (my ($key, $value) = each %$greplist) {
		for (0 .. $#lines) {
			(my $tmp = $lines[$_]) =~ s,/\*.*?\*/,,;
			if ($tmp =~ m/#[^\n]*\W$key\W/s) {
				undef %include_nest_check;
				if (($body !~ m/\W$value\W/) &&
				    !defined(found_include($path, 0, $value))) {
					printf "%s:%d: reference '$key' but not include $value (defined in $sym2files->{$key})\n", $label, $_ + 1;
				}
			}
		}
	}
}

exit;


sub found_include {
	my $path = shift;
	my $search = shift;
	my $includefile = shift;
	my $found;

	print STDERR "found_include($path, $includefile)\n" if ($opts{D});

	my @include = @INCLUDE;
	if ($search == 0) {
		@include = ('.');
	}

	for (@include) {
		my $file = "$_/$path";

		if (exists($include_nest_check{$file})) {
			return undef;
		}

		if (-f $file) {
			print STDERR "found_include: open: $file\n" if ($opts{D});
			my $fh = new IO::File $file, "r" or die "open: $file: $!\n";

			$include_nest_check{$file} = 1;
			while (<$fh>) {
				if (m/\W$includefile\W/) {
					$found = 1;
				} elsif (m/#\s*include\s+<(.*?)>/ or
				    m/#\s*include\s+"(.*?)"/) {

					print STDERR "found_include: include: $1\n" if ($opts{D});
					$found = found_include($1, 1, $includefile);
				}
				last if ($found);
			}
			$fh->close();
			last;
		}
		print STDERR "found_include: not found: $file\n" if ($opts{D});
	}

	$found;
}





#
# files.xxx parser
#
sub read_config {
	my $file = shift;
	my $fh = new IO::File $file, "r" or die "open: $file: $!\n";
	chop(my @lines = <$fh>);
	$fh->close();

	@lines = map { s/\s*#.*//; $_ } @lines;

	for (my $lineno = $#lines; $lineno >= 0; $lineno--) {
		next if ($lineno == 0);

		if ($lines[$lineno] =~ m/^\s/) {
			$lines[$lineno - 1] .= $lines[$lineno];
			$lines[$lineno] = '';
		}
	}

	@lines;
}

sub parse_defs {
	my @lines = @_;
	my $defdb;

	for (@lines) {
		if (m/^(defflag|defparam|deffs)\s+.*/) {
			my $deffile;
			(my $param = $_) =~ s/(:=|=|:|,)/ $1 /sg;

			my @params = split(/\s+/, $param);
			my $defmode = shift @params;

			if ($params[0] =~ m/^"(.*)"$/) {
				$params[0] = $1;
			}

			if ($params[0] =~ m/\.h$/) {
				$deffile = shift @params;
			}

			my @symbols;
			while ($#params >= 0) {
				if ($params[0] =~ m/[:=,]/) {
					shift @params;	# delete ':=', ':', ','
					shift @params;	# delete next param
				} else {
					push(@symbols, shift @params);
				}
			}


			for my $symbol (@symbols) {
				my $file = $deffile;
				$file = sprintf("opt_%s.h", lc($symbol)) unless (defined($deffile));
				push(@{$defdb->{$file}}, $symbol);
			}
		}
	}

	$defdb;
}

#!/usr/bin/env perl
#
# $Id: configlint,v 1.9 2015/08/26 09:16:30 ryo Exp $
#

use strict;
use warnings;

sub usage {
	die <<__USAGE__;
usage: configlint <kernel-configfile>
__USAGE__
}

usage() if ($#ARGV < 0);



my $obj = new CheckLine;

while (<>) {
	chop;
	$obj->checkline($_);
} continue {
	if (eof) {
		close ARGV;
		$obj = new CheckLine;
	}
}

exit;


package CheckLine;
use strict;
use warnings;

sub new {
	my $self = {};
	$self->{devname} = [''];
	$self->{parent} = [''];
	bless $self;
};

sub checkline {
	my $self = shift;
	$_ = my $line = shift;

	# if blank line, clear alphabetical order work
	if (m/^\s*$/) {
		$self->{devname} = [''];
		$self->{parent} = [''];
	}

	# check alphabetical arrangement for device declaration
	if (m/^#?([\w\*\?]+)\s+at\s+([\w\*\?]+)/) {
		my ($devname, $parent) = ($1, $2);
		$devname =~ s/[\*\?\d]$//sg;
		$parent  =~  s/[\*\?\d]$//sg;

		if ($parent eq ${$self->{devname}}[0]) {
			unshift(@{$self->{devname}}, '');
		} elsif ($parent ne ${$self->{parent}}[0]) {
			shift(@{$self->{devname}});
			push(@{$self->{devname}}, '');
		}

		if (($devname cmp ${$self->{devname}}[0]) < 0) {
			warning("incorrect alphabetical order\n");
		}

		${$self->{devname}}[0] = $devname;
		${$self->{parent}}[0] = $parent;
	}


	# check meaningless mixing <SPACE> and <TAB>
	if (m/^\s+$/) {
		warning("meaningless spaces\n");

	} elsif (m/^(#?)((?:no )?[-_\w\*\?]+)(\s+)/) {
		# this match; "no options ...", "options ...", "dev* at ...", etc

		my $comment = ($1 ne '');
		my $keyword = $2;
		my $space = $3;

		if (tabstop(length($keyword) + 1)) {
			if ($space =~ m/^\t/) {
				warning(qq'use <SPACE> instead of <TAB> after "$keyword"\n');
			}
			if ($space =~ m/  /) {
				warning(qq'use <SPACE> and <TAB> after "$keyword"\n');
			}
		} else {
			if ($space =~ m/^ \t/) {
				warning(qq(no need <SPACE> after "$keyword"\n));
			} elsif ($space =~ m/( \t|\t )/) {
				warning(qq(don't mix <SPACE> and <TAB> after "$keyword"\n));
			} elsif ($space =~ m/^ +$/) {
				if (tabstop($comment + length($keyword) + length($space)) ||
				    (length($space) != 1)) {
					warning(qq'use <TAB> after "$keyword"\n');
				}
			}
		}
	}

	# check meaningless <SPACE> before "#"
	if ($line =~ m/^([^#]*?)(\s+)#/) {
		my $defs = $1;
		my $space = $2;
		if (($space =~ m/ /) && (length($space) != 1)) {
			if (($defs =~ m/\t/) || ((length($defs) & 7) != 7) ||
			    ($space !~ m/^ \t*/)) {
				warning(qq'use <TAB> instead of a number of <SPACE> before "#"\n');
			}
		}
	}

	# check meaningless trailing space
	if ($line =~ m/\S\s+$/) {
		warning("unnecessarily trailing spaces\n");
	}
}

sub tabstop {
	my $len = shift;
	(($len & 7) == 0)
}

sub warning {
	print join(":", $ARGV, $., " Warning: "), @_;
}

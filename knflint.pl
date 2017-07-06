#!/usr/local/bin/perl
#
# $Id: knflint,v 1.13 2017/07/06 06:39:37 ryo Exp $
#

require 5.10.0;	# for nested regexp
use strict;
use warnings;
use Getopt::Std;
use IO::File;
use Data::Dumper;

sub usage {
	die <<__USAGE__;
knflint [options] [file ...]
	-D	debug
	-v	verbose
__USAGE__
}


my @reserved = qw(
	asm auto break case char const continue default define defined do double
	elif else endif enum extern float for goto if ifdef ifndef include inline int
	long pragma register return short signed sizeof static struct switch
	typedef typeof undef union unsigned void volatile while
);

my $RE_SYMBOL = qr/[_a-z]\w*/i;
my $RE_PAREN = qr/(\((?:[^()]++|(?-1))*+\))/;
my $RE_BLOCK = qr/(\{(?:[^\{\}]++|(?-1))*+\})/;



my %opts;
getopts('Dv', \%opts) or usage();

knflint($_) for (@ARGV);
exit;

sub knflint {
	my $file = shift;

	if (exists $opts{v}) {
		print $file, "\n";
	}

	my $r = new FileReader;
	$r->read($file) or return;

	check_column($r);
	check_lastcomma($r);
#	check_comment($r);	# check and eliminate comment with whitespace; destructive update
#	check_macro($r);	# eliminate preprocessor macro; destructive update

#	check_enum($r);
	check_struct($r);

	check_decl($r);
}

sub check_column {
	my $r = shift;

	my @lines = $r->lines;

	my $lineno = 1;
	for (@lines) {
		chop;
		if (m/ \t/) {
			printf "%s:%d: mixed space and tab\n", $r->path(), $lineno;
		}
		if (m/\s+$/) {
			printf "%s:%d: unnecessary spaces at the end of line\n", $r->path(), $lineno;
		}
		if (m/^ {8}/ || m/\t {8}/) {
			printf "%s:%d: continuous space. use tab\n", $r->path(), $lineno;
		} elsif (m/^ {5,7}/ || m/\t {5,7}/) {
			printf "%s:%d: Illegal length of space. Second level indents are four spaces\n", $r->path(), $lineno;
		}

		if (length(detab($_)) > 80) {
			if (!m/^__KERNEL_RCSID/ &&
			    !m/\$NetBSD:.*\$/ &&
			    !m/\$FreeBSD:.*\$/ &&
			    !m/\$OpenBSD:.*\$/) {
				printf "%s:%d: over 80 columns\n", $r->path(), $lineno;
			}
		}

	} continue {
		$lineno++;
	}
}

sub detab {
	my $line = shift;
	while ((my $i = index($line, "\t")) >= 0) {
		substr($line, $i, 1) = " " x (8 - ( $i % 8));
	}
	$line;
}

sub check_comment {
	my $r = shift;
	my $body = $r->body;

	# eliminate comment and call check function
	$body =~ s#(/\*[^*]*\*+(?:[^/*][^*]*\*+)*/)|("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\n+|.[^/"'\\]*)#check_comment_main0($r, $1); (defined $1 ? (' ' x length($1)) : '') . (defined $2 ? $2 : '')#seg;

	$r->body($body);
}

sub check_comment_main0 {
	my $r = shift;
	my $comment = shift;
	return unless (defined $comment);

	my $offset = $-[0];
	chop(my $startline = $r->offset2line($offset));
	my @comments = split(/\n/, $comment);
	if ($startline ne $comments[0]) {
		$comments[0] = (' ' x (length($startline) - length($comments[0]))) . $comments[0];
	}
	check_comment_main($r, $offset, join("\n", @comments));
}

#
# check_comment_main($reader, $offset, "     /* comment */");
#
sub check_comment_main {
	my $r = shift;
	my $offset = shift;
	my $comment = shift;

	die "XXX: not supported yet\n";
#	print "<COMMENT $offset>$comment</COMMENT>\n\n";
}


sub check_lastcomma {
	my $r = shift;
	my $body = $r->body;

	$body =~ s#(,\s*\})#check_lastcomma_main($r, $1)#seg;
}

sub check_lastcomma_main {
	my $r = shift;
	my $match = shift;
	my $offset = $-[0];

	my $lineno = $r->offset2lineno($offset);
	printf "%s:%d: No comma on the last element\n", $r->path(), $lineno + 1;
	$match;
}


sub check_struct {
	my $r = shift;
	my $body = $r->body;

	$body =~ s#\b(struct\s+\w+\s*\{)(.*?)(\})#check_struct_main($r, $1, $2, $3)#seg;
}

sub check_struct_main {
	my $r = shift;
	my $struct_begin = shift;
	my $struct_body = shift;
	my $struct_end = shift;
	my $match = join('<>', $struct_begin, $struct_body, $struct_end);

	my $offset = $-[0];

	if (($struct_body =~ m/\bstruct\s*\{/) ||
	    ($struct_body =~ m/\bstruct\s+\w+\s*\{/)) {
		$offset += length($struct_begin) + $-[0] + 1;

		my $lineno = $r->offset2lineno($offset);
		printf "%s:%d: nested struct\n", $r->path(), $lineno + 1;
	}
	$match;
}


sub check_macro {
	my $r = shift;

	die "XXX: not supported yet\n";

	my $body = $r->body;
	$r->body($body);
}

sub check_decl {
	my $r = shift;

	my $body = $r->body;

	my @lines = $r->lines;
	my $analyzed;
	my $offset = 0;

	my $RE_ARGCLASS = qr/[\[\]_\w\*\,\s\(\)]+/;

	while ($body =~ m/($RE_SYMBOL)\s*(${RE_PAREN})\s*((?:$RE_ARGCLASS\s*;\s*)*)\s*\{/sg) {
		my $funcname = $1;
		my $ansi_variables = $3;
		my $old_variables = $4;

		my $lineno = 1 + $r->offset2lineno($offset + $-[2]);

		$analyzed->{$funcname}->{lineno} = $lineno;
		$analyzed->{$funcname}->{arg} = $ansi_variables;
		$analyzed->{$funcname}->{oldarg} = $old_variables;

		if ((defined $old_variables) && ($old_variables !~ m/^\s*$/)) {
			printf "%s:%d: K&R type declaration\n", $r->path(), $lineno;
		}

		if (exists $opts{D}) {
			print "$funcname DONE\n";
		}
	}

#	print Dumper($analyzed);
}






package FileReader;
use Data::Dumper;

sub new {
	bless {};
}

sub read {
	my $self = shift;
	$self->{path} = shift;

	open(my $fh, '<', $self->{path}) or do {
		warn "$self->{path}: $!\n";
		return undef;
	};

	$self->{fh} = $fh;
	@{$self->{lines}} = <$fh>;
	$self->{body} = join("", @{$self->{lines}});
	$self->{original} = $self->{body};

	my $offset = 0;
	my $line = 0;
	for (@{$self->{lines}}) {
		$self->{offset2line}->{$offset} = $_;
		$self->{offset2lineno}->{$offset} = $line++;
		$offset += length($_);
	}

	return 1;
}

sub path {
	my $self = shift;
	$self->{path};
}

sub body {
	my $self = shift;
	$self->{body} = shift if @_;
	$self->{body};
}

sub lines {
	my $self = shift;
	@{$self->{lines}};
}

sub offset2lineno {
	my $self = shift;
	my $offset = shift;
	my @keys = sort { $a <=> $b } keys(%{$self->{offset2lineno}});

	my $lineno;
	for (@keys) {
		last if ($_ > $offset);
		$lineno = $self->{offset2lineno}->{$_};
	}
	$lineno;
}

sub offset2line {
	my $self = shift;
	my $offset = shift;
	my @keys = sort { $a <=> $b } keys(%{$self->{offset2line}});

	my $line;
	for (@keys) {
		last if ($_ > $offset);
		$line = $self->{offset2line}->{$_};
	}
	$line;
}

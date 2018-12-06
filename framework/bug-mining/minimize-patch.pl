#!/usr/bin/env perl
#
#-------------------------------------------------------------------------------
# Copyright (c) 2014-2018 René Just, Darioush Jalali, and Defects4J contributors.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#-------------------------------------------------------------------------------

=pod

=head1 NAME

minimize-patch.pl -- View and minimize patch in a visual diff editor. If a patch
is minimized, the script recomputes all metadata by rerunning the
get-metadata.pl.

=head1 SYNOPSIS

minimize-patch.pl -p project_id -b bug_id -w work_dir

=head1 OPTIONS

=over 4

=item B<-p C<project_id>>

The id of the project for which the patch should be displayed.

=item B<-b C<bug_id>>

The id of the bug for which the patch should be displayed.

=item B<-w F<work_dir>>

The working directory used for the bug-mining process.

=back

=cut
use warnings;
use strict;
use FindBin;
use File::Basename;
use Cwd qw(abs_path);
use Getopt::Std;
use Pod::Usage;

use lib abs_path("$FindBin::Bin/../core");
use Constants;
use Project;

my %cmd_opts;
getopts('p:b:w:', \%cmd_opts) or pod2usage(1);

pod2usage(1) unless defined $cmd_opts{p} and defined $cmd_opts{b} and defined $cmd_opts{w};

=pod

=head1 EDITOR

The default editor (merge tool) used to visualize patches is meld. A different
editor can be set via the environment variable D4J_EDITOR.

=cut
my $EDITOR = $ENV{"D4J_EDITOR"} // "meld";

my $PID = $cmd_opts{p};
my $BID = $cmd_opts{b};
my $WORK_DIR = abs_path($cmd_opts{w});

# Check format of target version id
$BID =~ /^(\d+)$/ or die "Wrong version id format: $BID -- expected: (\\d+)!";

# Add script and core directory to @INC
unshift(@INC, "$WORK_DIR/framework/core");

# Override global constants
$REPO_DIR = "$WORK_DIR/project_repos";
$PROJECTS_DIR = "$WORK_DIR/framework/projects";

# Set the projects and repository directories to the current working directory.
my $PROJECTS_DIR = "$WORK_DIR/framework/projects";
my $PROJECTS_REPOS_DIR = "$WORK_DIR/project_repos";

my $PATCH_DIR = "$PROJECTS_DIR/$PID/patches";
-d $PATCH_DIR or die "Cannot read patch directory: $PATCH_DIR";

my $TMP_DIR = Utils::get_tmp_dir();
system("mkdir -p $TMP_DIR");

my $src_patch = "$BID.src.patch";

# Set up project
my $project = Project::create_project($PID);
$project->{prog_root} = $TMP_DIR;

my $src_path = $project->src_dir("${BID}f");
$project->checkout_vid("${BID}f", $TMP_DIR, 1);
$project->apply_patch($TMP_DIR, "$PATCH_DIR/$src_patch") or die "Cannot apply patch";

# Copy the non-minimized patch
Utils::exec_cmd("cp $PATCH_DIR/$src_patch $TMP_DIR", "Back up original patch")
        or die "Cannot backup patch file";

# Minimize patch with configured editor
system("$EDITOR $TMP_DIR");

# Check whether patch could be successfully minimized
print "Patch minimized? [y/n] >";
my $input = <STDIN>; chomp $input;
exit 0 unless lc $input eq "y";

my $orig=`cd $TMP_DIR; git log | head -1 | cut -f2 -d' '`;
chomp $orig;
system("cd $TMP_DIR; git commit -a -m \"minimized patch\"");
my $min=`cd $TMP_DIR; git log | head -1 | cut -f2 -d' '`;
chomp $min;

# Last chance to reject patch
system("cd $TMP_DIR; git diff $orig $min -- $src_path $src_path");
print "Patch correct? [y/n] >";
$input = <STDIN>; chomp $input;
exit 0 unless lc $input eq "y";

# Store minimized patch
Utils::exec_cmd("cd $TMP_DIR; git diff $orig $min -- $src_path $src_path > $PATCH_DIR/$src_patch",
        "Export minimized patch") or die "Cannot export patch";

# Run sanity check
# Export variables to make sure the sanity check script picks up the right directories.
$ENV{'PROJECTS_DIR'} = abs_path($PROJECTS_DIR);
$ENV{'REPO_DIR'} = abs_path($PROJECTS_REPOS_DIR);
# TODO: This should also be configurable in Constants.pm
$ENV{'PERL5LIB'} = "$WORK_DIR/framework/core";
if (!Utils::exec_cmd("$UTIL_DIR/sanity_check.pl -p$PID -b$BID", "Run sanity check")) {
    Utils::exec_cmd("cp $TMP_DIR/$src_patch $PATCH_DIR", "Restore original patch")
            or die "Cannot restore patch";
}

# Re-run get-metadata script as metadata might have changed
if (!Utils::exec_cmd("./get-metadata.pl -p $PID -w $WORK_DIR -b $BID", "Re-running get-metadata script as metadata might have changed")) {
    Utils::exec_cmd("cp $TMP_DIR/$src_patch $PATCH_DIR", "Restore original patch")
            or die "Cannot restore patch";
}

# Remove temporary directory
system("rm -rf $TMP_DIR");

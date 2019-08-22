# Copyright (C) 2014-2019 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";
use Test::More;
use Test::Mojo;
use Test::Warnings;
use OpenQA::Test::Case;

my $test_case = OpenQA::Test::Case->new;
$test_case->init_data;

my $t      = Test::Mojo->new('OpenQA::WebAPI');
my $schema = $t->app->schema;

sub get_summary {
    return OpenQA::Test::Case::trim_whitespace($t->tx->res->dom->at('#summary')->all_text);
}

#
# Overview of build 0091
#
$schema->resultset('Jobs')->find(99928)->update({blocked_by_id => 99927});
$t->get_ok('/tests/overview' => form => {distri => 'opensuse', version => '13.1', build => '0091'})->status_is(200);

my $summary = get_summary;
like($summary, qr/Overall Summary of opensuse 13\.1 build 0091/i);
like($summary, qr/Passed: 3 Failed: 0 Scheduled: 2 Running: 2 None: 1/i);

# Check the headers
$t->element_exists('#flavor_DVD_arch_i586');
$t->element_exists('#flavor_DVD_arch_x86_64');
$t->element_exists('#flavor_GNOME-Live_arch_i686');
$t->element_exists_not('#flavor_GNOME-Live_arch_x86_64');
$t->element_exists_not('#flavor_DVD_arch_i686');

# Check some results (and it's overview_xxx classes)
$t->element_exists('#res_DVD_i586_kde .result_passed');
$t->element_exists('#res_GNOME-Live_i686_RAID0 i.state_cancelled');
$t->element_exists('#res_DVD_i586_RAID1 i.state_blocked');
$t->element_exists_not('#res_DVD_x86_64_doc');

# Check distinction between scheduled and blocked
my $dom = $t->tx->res->dom;
is_deeply($dom->find('.status.state_scheduled')->map('parent')->map(attr => 'href')->to_array,
    ['/tests/99927'], '99927 is scheduled');
is_deeply($dom->find('.status.state_blocked')->map('parent')->map(attr => 'href')->to_array,
    ['/tests/99928'], '99928 is blocked');

my $form = {distri => 'opensuse', version => '13.1', build => '0091', group => 'opensuse 13.1'};
$t->get_ok('/tests/overview' => form => $form)->status_is(200);
like(get_summary, qr/Overall Summary of opensuse 13\.1 build 0091/i, 'specifying group parameter');
$form = {distri => 'opensuse', version => '13.1', build => '0091', groupid => 1001};
$t->get_ok('/tests/overview' => form => $form)->status_is(200);
like(get_summary, qr/Overall Summary of opensuse build 0091/i, 'specifying groupid parameter');
subtest 'escaping works' => sub {
    $form = {
        distri  => '<img src="distri">',
        version => ['<img src="version1">', '<img src="version2">'],
        build   => '<img src="build">'
    };
    $t->get_ok('/tests/overview' => form => $form)->status_is(200);
    my $body = $t->tx->res->body;
    unlike($body, qr/<img src="distri">/,                         'no unescaped image tag for distri');
    unlike($body, qr/<img src="version1">.*<img src="version2">/, 'no unescaped image tags for version');
    unlike($body, qr/<img src="build">/,                          'no unescaped image tag for build');
    like($body, qr/&lt;img src=&quot;distri&quot;&gt;/, 'image tag for distri escaped');
    like(
        $body,
        qr/&lt;img src=&quot;version1&quot;&gt;.*&lt;img src=&quot;version2&quot;&gt;/,
        'image tags for version escaped'
    );
    like($body, qr/&lt;img src=&quot;build&quot;&gt;/, 'image tag for build escaped');
};

#
# Overview of build 0048
#
$t->get_ok('/tests/overview' => form => {distri => 'opensuse', version => 'Factory', build => '0048'})->status_is(200);
like(get_summary, qr/\QPassed: 0 Soft-Failed: 2 Failed: 1\E/i);

# Check the headers
$t->element_exists('#flavor_DVD_arch_x86_64');
$t->element_exists_not('#flavor_DVD_arch_i586');
$t->element_exists_not('#flavor_GNOME-Live_arch_i686');

# Check some results (and it's overview_xxx classes)
$t->element_exists('#res_DVD_x86_64_doc .result_failed');
$t->element_exists('#res_DVD_x86_64_kde .result_softfailed');
$t->element_exists_not('#res_DVD_i586_doc');
$t->element_exists_not('#res_DVD_i686_doc');

my $failedmodules
  = OpenQA::Test::Case::trim_whitespace($t->tx->res->dom->at('#res_DVD_x86_64_doc .failedmodule')->all_text);
like($failedmodules, qr/logpackages/i, "failed modules are listed");

#
# Default overview for 13.1
#
$t->get_ok('/tests/overview' => form => {distri => 'opensuse', version => '13.1'})->status_is(200);
$summary = get_summary;
like($summary, qr/Summary of opensuse 13\.1 build 0091/i);
like($summary, qr/Passed: 3 Failed: 0 Scheduled: 2 Running: 2 None: 1/i);

$form = {distri => 'opensuse', version => '13.1', groupid => 1001};
$t->get_ok('/tests/overview' => form => $form)->status_is(200);
like(
    get_summary,
    qr/Summary of opensuse build 0091/i,
    'specifying job group but with no build yields latest build in this group'
);

#
# Default overview for Factory
#
$t->get_ok('/tests/overview' => form => {distri => 'opensuse', version => 'Factory'})->status_is(200);
$summary = get_summary;
like($summary, qr/Summary of opensuse Factory build 0048\@0815/i);
like($summary, qr/\QPassed: 0 Failed: 1\E/i);


#
# Still possible to check an old build
#
$t->get_ok('/tests/overview' => form => {distri => 'opensuse', version => 'Factory', build => '87.5011'})
  ->status_is(200);
$summary = get_summary;
like($summary, qr/Summary of opensuse Factory build 87.5011/);
like($summary, qr/Passed: 0 Incomplete: 1 Failed: 0/);

# Advanced query parameters can be forwarded
$form = {distri => 'opensuse', version => '13.1', result => 'passed'};
$t->get_ok('/tests/overview' => form => $form)->status_is(200);
$summary = get_summary;
like($summary, qr/Summary of opensuse 13\.1 build 0091/i, "Still references the last build");
like($summary, qr/Passed: 3 Failed: 0/i, "Only passed are shown");
$t->element_exists('#res_DVD_i586_kde .result_passed');
$t->element_exists('#res_DVD_i586_textmode .result_passed');
$t->element_exists_not('#res_DVD_i586_RAID0 .state_scheduled');
$t->element_exists_not('#res_DVD_x86_64_kde .state_running');
$t->element_exists_not('#res_GNOME-Live_i686_RAID0 .state_cancelled');
$t->element_exists_not('.result_failed');
$t->element_exists_not('.state_cancelled');

# This time show only failed
$form = {distri => 'opensuse', version => 'Factory', build => '0048', result => 'failed'};
$t->get_ok('/tests/overview' => form => $form)->status_is(200);
like(get_summary, qr/Passed: 0 Failed: 1/i);
$t->element_exists('#res_DVD_x86_64_doc .result_failed');
$t->element_exists_not('#res_DVD_x86_64_kde .result_passed');

$form = {distri => 'opensuse', version => 'Factory', build => '0048', todo => 1};
$t->get_ok('/tests/overview' => form => $form)->status_is(200);
like(get_summary, qr/Passed: 0 Failed: 1/i, 'todo=1 shows only unlabeled left failed');

# add a failing module to one of the softfails to test 'TODO' option
my $failing_module = $t->app->schema->resultset('JobModules')->create(
    {
        script   => 'tests/x11/failing_module.pm',
        job_id   => 99936,
        category => 'x11',
        name     => 'failing_module',
        result   => 'failed'
    });

$t->get_ok('/tests/overview' => form => {distri => 'opensuse', version => 'Factory', build => '0048', todo => 1})
  ->status_is(200);
like(
    get_summary,
    qr/Passed: 0 Soft-Failed: 1 Failed: 1/i,
    'todo=1 shows only unlabeled left failed (previously softfailed) was labeled'
);
$t->element_exists_not('#res-99939', 'softfailed filtered out');
$t->element_exists('#res-99936', 'unreviewed failed because of new failing module present');

my $review_comment = $t->app->schema->resultset('Comments')->create(
    {
        job_id  => 99936,
        text    => 'bsc#1234',
        user_id => 99903,
    });
$t->get_ok('/tests/overview' => form => {distri => 'opensuse', version => 'Factory', build => '0048', todo => 1})
  ->status_is(200);
like(get_summary, qr/Passed: 0 Failed: 1/i, 'todo=1 shows only unlabeled left failed after new failed was labeled');
$t->element_exists_not('#res-99936', 'reviewed failed filtered out');

$review_comment->delete();
$failing_module->delete();

# multiple groups can be shown at the same time
$t->get_ok('/tests/overview?distri=opensuse&version=13.1&groupid=1001&groupid=1002&build=0091')->status_is(200);
$summary = get_summary;
like($summary, qr/Summary of opensuse, opensuse test/i, 'references both groups selected by query');
like($summary, qr/Passed: 2 Failed: 0 Scheduled: 1 Running: 2 None: 1/i,
    'shows latest jobs from both groups 1001/1002');
$t->element_exists('#res_DVD_i586_kde',                           'job from group 1001 is shown');
$t->element_exists('#res_GNOME-Live_i686_RAID0 .state_cancelled', 'another job from group 1001');
$t->element_exists('#res_NET_x86_64_kde .state_running',          'job from group 1002 is shown');

$t->get_ok('/tests/overview?distri=opensuse&version=13.1&groupid=1001&groupid=1002')->status_is(200);
$summary = get_summary;
like(
    $summary,
    qr/Summary of opensuse, opensuse test/i,
    'multiple groups with no build specified yield latest build of first group'
);
like($summary, qr/Passed: 2 Failed: 0 Scheduled: 1 Running: 2 None: 1/i);

# overview page searches for all available data with less specified parameters
$t->get_ok('/tests/overview' => form => {build => '0091', version => '13.1'})->status_is(200);
$t->get_ok('/tests/overview' => form => {build => '0091', distri  => 'opensuse'})->status_is(200);
$t->get_ok('/tests/overview' => form => {build => '0091'})->status_is(200);
$t->get_ok('/tests/overview')->status_is(200);
$summary = get_summary;
like($summary, qr/Summary of opensuse/i, 'shows all available latest jobs for the only present distri');
like(
    $summary,
    qr/Passed: 3 Failed: 0 Scheduled: 2 Running: 2 None: 1/i,
    'shows latest jobs from all distri, version, build, flavor, arch'
);
$t->element_exists('#res_DVD_i586_kde');
$t->element_exists('#res_GNOME-Live_i686_RAID0 .state_cancelled');
$t->element_exists('#res_NET_x86_64_kde .state_running');

#
# Test filter form
#

# Test initial state of architecture text box
$form = {distri => 'opensuse', version => 'Factory', result => 'passed', arch => 'i686'};
$t->get_ok('/tests/overview' => form => $form)->status_is(200);
# FIXME: works when testing manually, but accessing the value via Mojo doesn't work
#is($t->tx->res->dom->at('#filter-arch')->val, 'i686', 'default state of architecture');

# more UI tests of the filter form are in t/ui/10-tests_overview.t based on phantomjs

$t->get_ok('/tests/99937/modules/kate/fails')->json_is('/failed_needles' => ["test-kate-1"], 'correct failed needles');
$t->get_ok('/tests/99937/modules/zypper_up/fails')
  ->json_is('/first_failed_step' => 1, 'failed module: fallback to first step');

# Check if logpackages has failed, filtering with failed_modules
$form = {distri => 'opensuse', version => 'Factory', failed_modules => 'logpackages'};
$t->get_ok('/tests/overview', form => $form)->status_is(200);
like(get_summary, qr/Passed: 0 Failed: 0/i, 'all jobs filtered out');
$t->element_exists_not('#res_DVD_x86_64_doc .result_failed', 'old job not revealed');
$t->element_exists_not('#res_DVD_x86_64_kde .result_passed', 'passed job hidden');

# make job with logpackages the latest by 'disabling' the currently latest
my $latest_job = $schema->resultset('Jobs')->find(99940);
$latest_job->update({DISTRI => 'not opensuse'});
$t->get_ok('/tests/overview', form => $form)->status_is(200);
like(get_summary, qr/Passed: 0 Failed: 1/i);
$t->element_exists('#res_DVD_x86_64_doc .result_failed', 'job with failed module logpackages still shown');
$t->element_exists_not('#res_DVD_x86_64_kde .result_passed', 'passed job hidden');

# Check if another random module has failed
$latest_job->update({DISTRI => 'opensuse'});
$failing_module = $schema->resultset('JobModules')->create(
    {
        script   => 'tests/x11/failing_module.pm',
        job_id   => 99940,
        category => 'x11',
        name     => 'failing_module',
        result   => 'failed'
    });
$t->get_ok(
    '/tests/overview' => form => {
        distri         => 'opensuse',
        version        => 'Factory',
        failed_modules => 'failing_module'
    })->status_is(200);

like(get_summary, qr/Passed: 0 Failed: 1/i, 'failed_modules shows failed jobs');
$t->element_exists('#res-99940',                         'foo_bar_failed_module failed');
$t->element_exists('#res_DVD_x86_64_doc .result_failed', 'foo_bar_failed_module module failed');

# Check if another random module has failed
$schema->resultset('JobModules')->create(
    {
        script   => 'tests/x11/failing_module.pm',
        job_id   => 99938,
        category => 'x11',
        name     => 'failing_module',
        result   => 'failed'
    });
$t->get_ok(
    '/tests/overview' => form => {
        distri         => 'opensuse',
        version        => 'Factory',
        failed_modules => 'failing_module,logpackages',
    })->status_is(200);
like(get_summary, qr/Passed: 0 Failed: 1/i, 'expected job failures matches');
$failedmodules = OpenQA::Test::Case::trim_whitespace($t->tx->res->dom->at('#res_DVD_x86_64_doc')->all_text);
is($failedmodules, 'failing_module', 'failing_module module failed');

# Check if failed_modules hides successful jobs even if a (fake) module failure is there
$failing_module = $schema->resultset('JobModules')->create(
    {
        script   => 'tests/x11/failing_module.pm',
        job_id   => 99946,
        category => 'x11',
        name     => 'failing_module',
        result   => 'failed'
    });
$t->get_ok(
    '/tests/overview' => form => {
        distri         => 'opensuse',
        version        => '13.1',
        failed_modules => 'failing_module',
    })->status_is(200);
like(get_summary, qr/Passed: 0 Failed: 0/i, 'Job was successful, so failed_modules does not show it');
$t->element_exists_not('#res-99946', 'no module has failed');

done_testing();

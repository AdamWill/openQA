#! /usr/bin/perl

# Copyright (C) 2014-2017 SUSE LLC
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

BEGIN {
    unshift @INC, 'lib';
    $ENV{OPENQA_TEST_IPC} = 1;

}

use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use Test::Mojo;
use Date::Format 'time2str';
use Test::Warnings ':all';
use OpenQA::Test::Case;
use Time::HiRes qw(sleep);
use OpenQA::SeleniumTest;
use Mojo::JSON 'decode_json';

my $test_case   = OpenQA::Test::Case->new;
my $schema_name = OpenQA::Test::Database->generate_schema_name;
my $schema      = $test_case->init_data(schema_name => $schema_name);

# ensure needle dir can be listed (might not be the case because previous test run failed)
my $needle_dir = 't/data/openqa/share/tests/opensuse/needles/';
chmod(0755, $needle_dir);

sub schema_hook {
    my $needles = $schema->resultset('Needles');
    $needles->create(
        {
            dir_id                 => 1,
            filename               => 'never-matched.json',
            last_seen_module_id    => 10,
            last_seen_time         => time2str('%Y-%m-%d %H:%M:%S', time - 100000),
            last_matched_module_id => undef,
            file_present           => 1,
        });
}
my $driver = call_driver(\&schema_hook, {with_gru => 1});
unless ($driver) {
    plan skip_all => $OpenQA::SeleniumTest::drivermissing;
    exit(0);
}

my @needle_files = qw(inst-timezone-text.json inst-timezone-text.png never-matched.json never-matched.png);
subtest 'create dummy files for needles' => sub {
    for my $file_name (@needle_files) {
        my $file_path = $needle_dir . $file_name;
        ok(open(my $file, '>', $file_path), $file_name . ' is created');
        print $file 'go away later';
        close($file);
    }
};

$driver->title_is("openQA", "on main page");
$driver->find_element_by_link_text('Login')->click();
# we're back on the main page
$driver->title_is("openQA", "back on main page");

sub goto_admin_needle_table {
    my $login_link = $driver->find_element('#user-action > a');
    is($login_link->get_text(), 'Logged in as Demo', 'logged in as demo');
    # the following should work, but apparently doesn't - at least when executing tests in Travis:
    #   $login_link->click();
    #   $driver->find_element_by_link_text('Needles')->click();
    # see https://github.com/os-autoinst/openQA/pull/1619#issuecomment-381554863
    # so navigate to admin needles page by using the URL directly
    $driver->get('/admin/needles');
    wait_for_ajax;
}
goto_admin_needle_table();

my @trs = $driver->find_elements('#needles tr', 'css');
# skip header
my @tds = $driver->find_child_elements($trs[1], 'td', 'css');
is((shift @tds)->get_text(),                   'fixtures',                "Path is fixtures");
is((shift @tds)->get_text(),                   'inst-timezone-text.json', "Name is right");
is((my $module_link = shift @tds)->get_text(), 'a day ago',               "last use is right");
is((shift @tds)->get_text(),                   'about 14 hours ago',      "last match is right");
@tds = $driver->find_child_elements($trs[2], 'td', 'css');
is((shift @tds)->get_text(), 'fixtures',           "Path is fixtures");
is((shift @tds)->get_text(), 'never-matched.json', "Name is right");
is((shift @tds)->get_text(), 'a day ago',          "last use is right");
is((shift @tds)->get_text(), 'never',              "last match is right");
$driver->find_child_element($module_link, 'a', 'css')->click();
like(
    $driver->execute_script("return window.location.href"),
    qr(\Q/tests/99937#step/partitioning_finish/1\E),
    "redirected to right module"
);

goto_admin_needle_table();

$driver->find_element_by_link_text('about 14 hours ago')->click();
like(
    $driver->execute_script("return window.location.href"),
    qr(\Q/tests/99937#step/partitioning/1\E),
    "redirected to right module too"
);

goto_admin_needle_table();

subtest 'delete needle' => sub {
    # disable animations to speed up test
    $driver->execute_script('$(\'#confirm_delete\').removeClass(\'fade\');');

    # select first needle and open modal dialog for deletion
    $driver->find_element('td input')->click();
    wait_for_ajax;
    $driver->find_element_by_id('delete_all')->click();

    is($driver->find_element_by_id('confirm_delete')->is_displayed(), 1, 'modal dialog');
    is($driver->find_element('#confirm_delete .modal-title')->get_text(), 'Needle deletion', 'title matches');
    is(scalar @{$driver->find_elements('#outstanding-needles li', 'css')}, 1, 'one needle outstanding for deletion');
    is(scalar @{$driver->find_elements('#failed-needles li',      'css')}, 0, 'no failed needles so far');
    is($driver->find_element('#outstanding-needles li')->get_text(),
        'inst-timezone-text.json', 'right needle name displayed');

    subtest 'error case' => sub {
        chmod(0444, $needle_dir);
        $driver->find_element_by_id('really_delete')->click();
        wait_for_ajax;
        is(scalar @{$driver->find_elements('#outstanding-needles li', 'css')}, 0, 'no outstanding needles');
        is(scalar @{$driver->find_elements('#failed-needles li',      'css')}, 1, 'but failed needle');
        is(
            $driver->find_element('#failed-needles li')->get_text(),
"inst-timezone-text.json\nUnable to delete t/data/openqa/share/tests/opensuse/needles/inst-timezone-text.json and t/data/openqa/share/tests/opensuse/needles/inst-timezone-text.png",
            'right needle name and error message displayed'
        );
        $driver->find_element_by_id('close_delete')->click();
    };

    # select all needles and re-open modal dialog for deletion
    wait_for_ajax;    # required due to server-side datatable
    $_->click() for $driver->find_elements('td input', 'css');
    $driver->find_element_by_id('delete_all')->click();
    my @outstanding_needles = $driver->find_elements('#outstanding-needles li', 'css');
    is(scalar @outstanding_needles, 2, 'still two needle outstanding for deletion');
    is((shift @outstanding_needles)->get_text(), 'inst-timezone-text.json', 'right needle names displayed');
    is((shift @outstanding_needles)->get_text(), 'never-matched.json',      'right needle names displayed');
    is(scalar @{$driver->find_elements('#failed-needles li', 'css')},
        0, 'failed needles from last time shouldn\'t appear again when reopening deletion dialog');

    subtest 'successful deletion' => sub {
        chmod(0755, $needle_dir);
        $driver->find_element_by_id('really_delete')->click();
        wait_for_ajax;
        is(scalar @{$driver->find_elements('#outstanding-needles li', 'css')}, 0, 'no outstanding needles');
        is(scalar @{$driver->find_elements('#failed-needles li',      'css')}, 0, 'no failed needles');
        $driver->find_element_by_id('close_delete')->click();
        wait_for_ajax;    # required due to server-side datatable
        for my $file_name (@needle_files) {
            is(-f $needle_dir . $file_name, undef, $file_name . ' is gone');
        }
        is($driver->find_element('#needles tbody tr')->get_text(), 'No data available in table', 'no needles left');
    };
};

subtest 'pass invalid IDs to needle deletion route' => sub {
    my $func = 'function(error) { window.deleteMsg = JSON.stringify(error); }';
    ok(
        !$driver->execute_script(
            "jQuery.ajax({url: '/admin/needles/delete?id=42&id=foo', type: 'DELETE', success: $func});"),
        'delete needle with ID 42'
    );
    wait_for_ajax;
    my $error = decode_json($driver->execute_script('return window.deleteMsg;'));
    is_deeply(
        $error,
        {
            errors => [
                {id => 42,    message => 'Unable to find needle with ID "42"'},
                {id => 'foo', message => 'Unable to find needle with ID "foo"'},
            ],
            removed_ids => []
        },
        'error returned'
    );
};

kill_driver();
done_testing();

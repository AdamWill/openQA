# Copyright (C) 2018 SUSE LLC
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
# You should have received a copy of the GNU General Public License

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib", "lib";

use Test::More;
use Test::Mojo;
use Mojo::URL;
use Test::Warnings;
use OpenQA::Client;
use OpenQA::Client::Archive;
use OpenQA::WebAPI;
use Mojo::File qw(tempfile tempdir path);
use OpenQA::Test::Case;

# init test case
OpenQA::Test::Case->new->init_data;
my $t = Test::Mojo->new('OpenQA::WebAPI');

# XXX: Test::Mojo loses it's app when setting a new ua
# https://github.com/kraih/mojo/issues/598
my $app = $t->app;
$t->ua(
    OpenQA::Client->new(apikey => 'PERCIVALKEY02', apisecret => 'PERCIVALSECRET02')->ioloop(Mojo::IOLoop->singleton));
$t->app($app);
my $base_url = $t->ua->server->url->to_string;

path('t', 'client_tests.d')->remove_tree;
my $destination = path('t', 'client_tests.d', tempdir)->make_path;

subtest 'OpenQA::Client:Archive tests' => sub {
    my $jobid     = 99938;
    my $resultdir = path($ENV{OPENQA_BASEDIR}, 'openqa', 'testresults');
    my $limit     = 1024 * 1024;
    system(
"dd if=/dev/zero of=$resultdir/00099/00099938-opensuse-Factory-DVD-x86_64-Build0048-doc/ulogs/limittest.tar.bz2 bs=1M count=2"
    );
    eval {
        my $command
          = $t->ua->archive->run(
            {archive => $destination, url => "/api/v1/jobs/$jobid/details", 'asset-size-limit' => $limit});
    };
    is($@, '', 'Archive functionality works as expected would perform correctly') or diag explain $@;

    my $file = path($destination, 'testresults', 'details-zypper_up.json');
    ok(-e $file, 'details-zypper_up.json file exists') or diag $file;
    $file = path($destination, 'testresults', 'video.ogv');

    ok(-e $file, 'Test video file exists') or diag $file;
    $file = path($destination, 'testresults', 'ulogs', 'y2logs.tar.bz2');

    ok(-e $file, 'Test uploaded logs file exists') or diag $file;
    $file = path($destination, 'testresults', 'ulogs', 'limittest.tar.bz2');

    ok(!-e $file, 'Test uploaded logs file was not created') or diag $file;
    is($t->ua->max_response_size, $limit, "Max response size for UA is correct ($limit)");
};

done_testing();

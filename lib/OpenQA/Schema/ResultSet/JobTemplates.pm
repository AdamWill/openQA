# Copyright (C) 2019 SUSE LLC
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

package OpenQA::Schema::ResultSet::JobTemplates;

use strict;
use warnings;

use base 'DBIx::Class::ResultSet';

sub create_or_update_job_template {
    my ($job_templates, $group_id, $args) = @_;

    my $schema                = $job_templates->result_source->schema;
    my $machines              = $schema->resultset('Machines');
    my $test_suites           = $schema->resultset('TestSuites');
    my $products              = $schema->resultset('Products');
    my $job_template_settings = $schema->resultset('JobTemplateSettings');

    die "Machine is empty and there is no default for architecture $args->{arch}\n"
      unless $args->{machine_name};

    # Find machine, product and testsuite
    my $machine = $machines->find({name => $args->{machine_name}});
    die "Machine '$args->{machine_name}' is invalid\n" unless $machine;
    my $product = $products->find(
        {
            arch    => $args->{arch},
            distri  => $args->{product_spec}->{distri},
            flavor  => $args->{product_spec}->{flavor},
            version => $args->{product_spec}->{version},
        });
    die "Product '$args->{product_name}' is invalid\n" unless $product;
    my $test_suite = $test_suites->find({name => $args->{testsuite_name}});
    die "Testsuite '$args->{testsuite_name}' is invalid\n" unless $test_suite;

    # Create/update job template
    my $job_template = $job_templates->find_or_create(
        {
            group_id      => $group_id,
            product_id    => $product->id,
            machine_id    => $machine->id,
            name          => $args->{job_template_name} // "",
            test_suite_id => $test_suite->id,
        },
        {
            key => 'scenario',
        });
    die "Job template name '"
      . ($args->{job_template_name} // $args->{testsuite_name})
      . "' with $args->{product_name} and $args->{machine_name} is already used in job group '"
      . $job_template->group->name . "'\n"
      if $job_template->group_id != $group_id;
    my $job_template_id = $job_template->id;
    $job_template->update({prio => $args->{prio}}) if (defined $args->{prio});

    # Add/update/remove parameter
    my @setting_ids;
    if ($args->{settings}) {
        foreach my $key (sort keys %{$args->{settings}}) {
            my $setting = $job_template_settings->find(
                {
                    job_template_id => $job_template_id,
                    key             => $key,
                });
            if ($setting) {
                $setting->update({value => $args->{settings}->{$key}});
            }
            else {
                $setting = $job_template_settings->find_or_create(
                    {
                        job_template_id => $job_template_id,
                        key             => $key,
                        value           => $args->{settings}->{$key},
                    });
            }
            push(@setting_ids, $setting->id);
        }
    }
    $job_template_settings->search(
        {
            id              => {'not in' => \@setting_ids},
            job_template_id => $job_template_id,
        })->delete();

    return $job_template_id;
}

1;

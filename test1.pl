#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Data::Dumper;
use Benchmark qw(:hireswallclock :all);

BEGIN {
	push @INC => './lib';
	require Cache::ARC;
}

sub test {
	my @keys;
	my %stats = (
		hit  => 0,
		miss => 0,
		call_count => { set => 0, get => 0 },
		time_total => { set => undef, get => undef }
	);
	
	my $iter_number = 50000;
	my $cache = Cache::ARC->new(size => 600);

	for (1 .. $iter_number) {
		my $key = int(rand() * 1000);
		my $value = "${key}_value";
		
		push @keys => $key;
		shift @keys if scalar @keys > 1000;
		
		my $t0 = Benchmark->new;
		$cache->set($key, $value);
		my $t1 = Benchmark->new;
		my $td = timediff($t1, $t0);
		if (!$stats{time_total}{set}) {
			$stats{time_total}{set} = $td;
		} else {
			$stats{time_total}{set} = timesum($stats{time_total}{set}, $td);
		}
		
		$stats{call_count}{set}++;
		
		if (rand() > 0.5) {
			my $key = $keys[ int rand scalar @keys ];
			
			my $t0 = Benchmark->new;
			my $val = $cache->get($key);
			my $t1 = Benchmark->new;
			my $td = timediff($t1, $t0);
			if (!$stats{time_total}{get}) {
				$stats{time_total}{get} = $td;
			} else {
				$stats{time_total}{get} = timesum($stats{time_total}{get}, $td);
			}
			
			$stats{call_count}{get}++;
			
			if ($val) {
				# print "get: cache hit, got value $val (key: $key)\n";
				$stats{hit}++;
			} else {
				# print "get: cache miss (key: $key)\n";
				$stats{miss}++;
			}
		}
		
		# $cache->print_state();
	}
	
	printf "done %s sets per %s\n", $stats{call_count}{set}, timestr($stats{time_total}{set});
	printf "done %s gets per %s\n", $stats{call_count}{get}, timestr($stats{time_total}{get});
	printf "%s hits, %s misses\n\n", @stats{ qw(hit miss) };
}

test() while (1);





use strict;
use warnings;
use utf8;

package Cache::ARC::List;

use Scalar::Util qw(weaken);

use constant PREV  => 0;
use constant NEXT  => 1;
use constant VALUE => 2;

use constant FIRST  => 0;
use constant LAST   => 1;
use constant LENGTH => 2;
use constant HASH   => 3;

sub new {
	return bless [ undef, undef, 0, {} ] => shift;
}

sub append_left {
	my ($self, $new_node) = @_;
	
	not UNIVERSAL::isa($new_node, 'ARRAY')
		and ( $new_node = [ undef, undef, $new_node ] );
	
	$self->contains($new_node->[VALUE])
		&& $self->remove($new_node->[VALUE]);
	
	if ( !defined $self->[FIRST] ) {
		$new_node->[PREV] = undef;
		$new_node->[NEXT] = undef;
		$self->[FIRST] = $new_node;
		$self->[LAST]  = $new_node;
	}
	else {
		my $first_node = $self->[FIRST];
		$new_node->[PREV] = $first_node->[PREV];
		$new_node->[NEXT] = $first_node;
		
		if (!defined $first_node->[PREV]) {
			$self->[FIRST] = $new_node;
		}
		else {
			$first_node->[PREV][NEXT] = $new_node;
		}
		
		$first_node->[PREV] = $new_node;
	}
	
	$self->[LENGTH]++;
	$self->[HASH]{ $new_node->[VALUE] } = $new_node;
}

sub remove {
	my ($self, $node) = @_;
	
	if ( !UNIVERSAL::isa($node, 'ARRAY') ) {
		# assume we got a string
		$node = $self->[HASH]{$node};
		die 'Illegal state' unless $node;
	} 
	
	if ( !defined $node->[PREV] ) {
		$self->[FIRST] = $node->[NEXT];
	}
	else {
		$node->[PREV][NEXT] = $node->[NEXT];
	}
	
	if ( !defined $node->[NEXT] ) {
		$self->[LAST] = $node->[PREV];
	}
	else {
		$node->[NEXT][PREV] = $node->[PREV];
	}
	
	$self->[LENGTH]--;
	
	my $value = $node->[VALUE];
	delete $self->[HASH]{$value};
	
	$node->[PREV] = undef;
	$node->[NEXT] = undef;
	weaken $node;
	
	return $value;
}

sub remove_last {
	my $self = shift;
	return unless $self->[LAST];
	return $self->remove($self->[LAST]);
}

sub contains {
	return exists $_[0]->[HASH]{ $_[1] };
}

sub length {
	return $_[0]->[LENGTH];
}

sub as_string {
	my $self = shift;
	
	my @res;
	my $node = $self->[FIRST];
	
	while (defined $node) {
		push @res => $node->[VALUE];
		$node = $node->[NEXT];
	}
	
	return join(' ', @res);
}

sub DESTROY {
	my $self = shift;
	
	my $node = $self->[FIRST];
	while (defined $node) {
		$node->[PREV] = undef;	
		$node = $node->[NEXT];
	}
	
	$self->[FIRST] = undef;
	$self->[LAST] = undef;
}


package Cache::ARC;

# http://www.cs.cmu.edu/~15-440/READINGS/megiddo-computer2004.pdf

use List::Util qw(min max);
use Storable qw(freeze thaw);

use constant LENGTH => Cache::ARC::List->LENGTH;

sub new {
	my $class = shift;
	my %args = (
		size => 100,
	@_);
	
	my $c = $args{size};
	$c and $c =~ /^\d+$/ and $c > 0
		or die 'Bad argument';
	
	my $self  = {
		c => $c,
		p => 0,
		cache => {},
		t1 => Cache::ARC::List->new,
		b1 => Cache::ARC::List->new,
		t2 => Cache::ARC::List->new,
		b2 => Cache::ARC::List->new,
	};
	
	return bless $self => $class;
}

sub load {
	my ($class, $dump) = @_;
	return thaw($dump);
}

sub dump {
	ref $_[0] or die 'Not a class method';
	return freeze($_[0]);
}

sub get {
	my ($self, $key) = @_;
	
	if ( $self->{t1}->contains($key) ) {
		$self->{t2}->append_left($self->{t1}->remove($key));
		return $self->{cache}{$key};
	}
	elsif ( $self->{t2}->contains($key) ) {
		$self->{t2}->append_left($self->{t2}->remove($key));
		return $self->{cache}{$key};
	}
	
	return undef;
}

sub set {
	my ($self, $key, $val) = @_;
	
	$self->{cache}{$key} = $val;
	$self->_adjust($key);
}

sub del {
	my ($self, $key) = @_;
	
	delete $self->{cache}{$key};
	foreach (qw(t1 t2 b1 b2)) {
		$self->{$_}->contains($key) && $self->{$_}->remove($key);
	}
}

sub _adjust {
	my ($self, $key) = @_;
	
	if ( $self->{b1}->contains($key) ) {
		$self->{p} = min(
			$self->{c},
			$self->{p} + max( $self->{b2}[LENGTH] / $self->{b1}[LENGTH], 1 )
		);
		
		$self->_replace($key);
		$self->{t2}->append_left($self->{b1}->remove($key));
	}
	elsif ( $self->{b2}->contains($key) ) {
		$self->{p} = max(
			0,
			$self->{p} - max( $self->{b1}[LENGTH] / $self->{b2}[LENGTH], 1 )
		);
		
		$self->_replace($key);
		$self->{t2}->append_left($self->{b2}->remove($key));
	}
	elsif ( !$self->{t1}->contains($key) && !$self->{t2}->contains($key) ) {
		if ( $self->{t1}[LENGTH] + $self->{b1}[LENGTH] == $self->{c} ) {
			if ( $self->{t1}[LENGTH] < $$self{c} ) {
				$self->{b1}->remove_last();
				$self->_replace($key);
			}
			else {
				delete $self->{cache}{ $self->{t1}->remove_last() };
			}
		}
		else {
			my $length_total = $self->{t1}[LENGTH] + $self->{t2}[LENGTH] +
				$self->{b1}[LENGTH] + $self->{b2}[LENGTH];
			
			if ( $self->{t1}[LENGTH] + $self->{b1}[LENGTH] < $$self{c}
				&& $length_total >= $self->{c} )
			{
				$self->{b2}->remove_last() if $length_total == 2 * $self->{c};
				$self->_replace($key);
			}
		}
		
		$self->{t1}->append_left($key);
	}
}

sub _replace {
	my ($self, $key) = @_;
	
	my $item;
	if ( $self->{t1}[LENGTH] >= 1
		&& ( ($self->{b2}->contains($key) && $self->{t1}[LENGTH] == $self->{p} )
			|| $self->{t1}[LENGTH] > $self->{p} )
		)
	{
		$item = $self->{t1}->remove_last();
		$self->{b1}->append_left($item);
		delete $self->{cache}{$item};
	}
	elsif ( $item = $self->{t2}->remove_last()) {
		$self->{b2}->append_left($item);
		delete $self->{cache}{$item};
	}
}

sub print_state {
	my $self = shift;
	printf("t1 len: %s, b1 len: %s, t2 len: %s, b2 len: %s, p: %s, c: %s\n",
		$self->{t1}[LENGTH], $self->{b1}[LENGTH],
		$self->{t2}[LENGTH], $self->{b2}[LENGTH],
		$self->{p},
		$self->{c});
}

1;

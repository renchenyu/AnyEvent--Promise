package AnyEvent::Promise;
use strict;
use warnings;

use AnyEvent;

use Exporter 'import';
our @EXPORT_OK = qw/promise/;
our @EXPORT = qw/promise/;


#cb sub { my ($global, $cv, $value) = @_; ... }
sub promise {
    __PACKAGE__->new(shift);
}

sub new {
    my ( $class, $cb ) = @_;
    my $self = { cb => $cb };
    bless $self, $class;
}

sub nxt {
    my ( $self, $cb ) = @_;
    my $global = $self->{global};
    __PACKAGE__->new(
        sub {
            my ( $global, $cv, $value ) = @_;
            my $nxt_cv = AnyEvent->condvar;
            $nxt_cv->cb( sub { $cb->( $global, $cv, shift->recv ); } );
            $self->{cb}->( $global, $nxt_cv, $value );
        }
    );
}

sub parallel {
    my ( $self, @cbs ) = @_;

    my $cb = sub {
        my ( $global, $cv, $value ) = @_;
        my $shared = {};

        my $s_cv = AnyEvent->condvar;
        $s_cv->begin( sub { $cv->send($shared) } );

        foreach my $cb (@cbs) {
            $s_cv->begin;
            $cb->( $global, $s_cv, $value, $shared );
        }

        $s_cv->end;
    };

    $self->nxt($cb);
}

sub run {
    my $self = shift;
    my ( $cv, $value, $global ) = @_;
    $self->{global} = $global;
    $self->{cb}->($global, $cv, $value);
}

1;

    

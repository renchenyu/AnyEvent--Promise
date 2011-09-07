#!/usr/bin/perl
use strict;
use warnings;

use Plack::Request;
use Plack::Response;
use AnyEvent::Redis;

use AnyEvent::Promise;

use Data::Dumper;

#$ENV{TWIGGY_DEBUG} = 1;

sub get_key {
    my $req    = shift;
    my $age    = $req->param('a') || 0;
    my $gender = $req->param('g') || 0;
    my $prov   = $req->param('p') || 0;
    my $city   = $req->param('c') || 0;
    my $job    = $req->param('j') || 0;
    my $key    = join "_", $age, $gender, $prov, $city, $job;
    return $key;
}

sub get_count {
    my ( $global, $cv, $key ) = @_;
    $global->{redis}->llen(
        $key,
        sub {
 #           warn "get_count\n";
            $cv->send([$key, shift]);
        }
    );
}

sub get_ad_id {
    my ( $global, $cv, $value ) = @_;
    my ( $key, $count ) = @$value;
    if ( $count && $count > 0 ) {
        my $index = int( rand($count) );
        $global->{redis}->lindex(
            $key,
            sub {

                #              warn "get_ad_id\n";
                $cv->send(shift);

            }
        );
    }
    else {

        #     warn "get_ad_id\n";
        $cv->send(1);
    }
}

sub _get_attributes {
    my ( $global, $cv, $ad_id, $shared, $attr_name ) = @_;
    $global->{redis}->get(
        "ad_${ad_id}:$attr_name",
        sub {
    #        warn "get $attr_name\n";
            $shared->{$attr_name} = shift;
            $cv->end;
        }
    );
}

sub get_url {
    _get_attributes(@_, "url");
}

sub get_src {
    _get_attributes(@_, "src");
}

sub get_alt {
    _get_attributes( @_, "alt" );
}

sub send_res {
    my ( $global, $cv, $value ) = @_;
    my $res = Plack::Response->new(200);
    $res->body( '<a href="'
            . $value->{url}
            . '"><img src="'
            . $value->{src}
            . '" alt="'
            . $value->{alt}
            . '" /></a>' );

    #warn "send_res\n";
    $cv->send( $res->finalize );
}

my $redis = AnyEvent::Redis->new(
    host     => "127.0.0.1",
    port     => 8722,
    encoding => "utf8"
);

my $app = sub {
    my $env = shift;
    my $req = Plack::Request->new($env);

    my $key = get_key($req);

    my $cv = AnyEvent->condvar;
    promise( \&get_count )->nxt( \&get_ad_id )
        ->parallel( \&get_url, \&get_src, \&get_alt )->nxt( \&send_res )
        ->run( $cv, $key, { redis => $redis } );

    return sub {
        my ( $callback, $sock ) = @_;
        $cv->cb( sub { $callback->( shift->recv ) } );
    };

};


use Mojolicious::Lite;

use lib '/var/mojo/lib/Mojolicious-Plugin-OAuth2Accounts/lib';
use lib '/var/mojo/apps/sohn_timeclock/lib';

use Mojo::Pg;
use TimeClock::Model::OAuth2;
use TimeClock::Model::Timeclock;

my $config = plugin 'Config';

helper 'pg' => sub { state $pg = Mojo::Pg->new(shift->config('pg')) };
helper 'model.oauth2' => sub { state $users = TimeClock::Model::OAuth2->new(pg => shift->pg) };
helper 'model.timeclock' => sub { state $timeclock = TimeClock::Model::Timeclock->new(pg => shift->pg) };
app->sessions->default_expiration(86400*365*10);
app->pg->migrations->from_data->migrate;

plugin "OAuth2Accounts" => {
  on_logout => '/',
  on_success => 'timeclock',
  on_error => 'connect',
  on_connect => sub { shift->model->oauth2->store(@_) },
  providers => $config->{oauth2},
};

get '/' => sub {
  my $c = shift;
  return $c->redirect_to('connectprovider', {provider => 'facebook'}) unless $c->session('id');
  $c->stash(user => $c->model->oauth2->find($c->session('id')));
  $c->stash(timeclock => $c->model->timeclock);
} => 'timeclock';

post '/' => sub {
  my $c = shift;
  return $c->reply->not_found unless $c->session('id');
  if ( $c->param('clock') eq 'in' ) {
    $c->model->timeclock->clock_in($c->session('id'), $c->param('lat'), $c->param('lon'));
  } elsif ( $c->param('clock') eq 'out' ) {
    $c->model->timeclock->clock_out($c->session('id'), $c->param('lat'), $c->param('lon'));
  }
  $c->redirect_to('timeclock');
} => 'timeclock';

get '/status' => sub {
  my $c = shift;
  return $c->redirect_to('timeclock') unless $c->session('id') && $c->model->oauth2->find($c->session('id'))->{admin};
  $c->stash(timeclock => $c->model->timeclock);
};

get '/history/:user' => sub {
  my $c = shift;
  return $c->redirect_to('timeclock') unless $c->session('id');
  return $c->reply->not_found unless $c->param('user') eq $c->session('id') || $c->model->oauth2->find($c->session('id'))->{admin};
  $c->stash(user => $c->param('user'));
  $c->stash(timeclock => $c->model->timeclock);
};

get '/pay/:user/:ids' => sub {
  my $c = shift;
  return $c->redirect_to('timeclock') unless $c->session('id') && $c->model->oauth2->find($c->session('id'))->{admin};
  $c->model->timeclock->pay(split /,/, $c->param('ids'));
  $c->stash(user => $c->param('user'));
  $c->stash(timeclock => $c->model->timeclock);
  $c->redirect_to('historyuser', {user => $c->param('user')});
} => 'payuser';

app->start;

__DATA__

@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
  <head>
    <style>
      * { font-size: 48px }
    </style>
    <title><%= title %></title>
  </head>
  <body><%= content %></body>
</html>

@@ historyuser.html.ep
% layout 'default';
% title 'User History';
% my $week;
<%= link_to "All user status" => 'status' %><hr />
% my $user_tc = $timeclock->user($user);
<%= "$user_tc->{first_name} $user_tc->{last_name}" %><br />
<table>
  <tr><th>week</th><th>Sunday</th><th>Monday</th><th>Tuesday</th><th>Wednesday</th><th>Thursday</th><th>Friday</th><th>Saturday</th><th>Total</th></tr>
% my $history = $timeclock->history($user);
% foreach my $week ( sort { $b cmp $a } keys %$history ) {
  <tr>
  <td><%= $week %>
  % my $week_time;
  % my $unpaid;
  % my @unpaid;
  % foreach my $dow ( qw/0 1 2 3 4 5 6/ ) {
    <td>
    % my $day_time;
    % foreach my $e ( @{$history->{$week}->{$dow}} ) {
      % $day_time = $day_time ? $day_time->add_duration($e->{duration}->clone) : $e->{duration}->clone;
      % $week_time = $week_time ? $week_time->add_duration($e->{duration}->clone) : $e->{duration}->clone;
      % $unpaid = $unpaid ? $unpaid->add_duration($e->{duration}->clone) : $e->{duration}->clone unless $e->{paid};
      % push @unpaid, $e->{id} if !$e->{paid};
      <%= link_to($e->{time_in}->hms => "https://www.google.com/maps/place//\@$e->{time_in_lat},$e->{time_in_lon},17z/data=!3m1!4b1!4m2!3m1!1s0x0:0x0") %> - <%= $e->{time_out} ? link_to($e->{time_out}->hms => "https://www.google.com/maps/place//\@$e->{time_in_lat},$e->{time_in_lon},17z/data=!3m1!4b1!4m2!3m1!1s0x0:0x0") : 'Active' %> (<%= $e->{paid} ? $timeclock->duration($e->{duration}) : link_to $timeclock->duration($e->{duration}) => 'payuser', {user => $user, ids => $e->{id}} %>)<br />
    % }
    % if ( $day_time ) {
      <b><%= $timeclock->duration($day_time) %></b>
    % }
    </td>
  % }
  <td>
  % if ( $unpaid ) {
    <b><%= link_to $timeclock->duration($unpaid, 1) => 'payuser', {user => $user, ids => join(',', @unpaid)} %></b><br />
  % }
  % if ( $week_time ) {
    <b><%= $timeclock->duration($week_time, 1) %></b><br />
  % }
  </td>
  </tr>
% }
</table>

@@ status.html.ep
% layout 'default';
% title 'All users';
<%= link_to 'My timeclock' => 'timeclock' %><hr />
% foreach my $user ( @{$timeclock->users} ) {
  % my $status = $timeclock->status($user->{id});
  % my $user_tc = $timeclock->user($user->{id});
  Name: <%= link_to "$user_tc->{first_name} $user_tc->{last_name}" => 'historyuser', {user => $user->{id}} %><br />
  Status: <%== $status ? "Active since ".link_to($status->{time_in}->datetime => "https://www.google.com/maps/place//\@$status->{time_in_lat},$status->{time_in_lon},17z/data=!3m1!4b1!4m2!3m1!1s0x0:0x0")." (".$timeclock->duration($status->{duration}).")" : 'Not active' %><hr />
% }

@@ timeclock.html.ep
% layout 'default';
% title 'My Timeclock';
<script src="http://maps.googleapis.com/maps/api/js?key=AIzaSyDKw1I9ZlI-piCBp2zXSuviBDVRjju-aYI&sensor=true&libraries=adsense"></script>
<script src="http://ctrlq.org/common/js/jquery.min.js"></script>   
<script>
  if ( "geolocation" in navigator ) {
    navigator.geolocation.getCurrentPosition(function(position){
      var lat = position.coords.latitude.toFixed(5);
      var lon = position.coords.longitude.toFixed(5);
      console.log(lat, lon);
      $('#lat').attr('value', lat);
      $('#lon').attr('value', lon);
      $('#div_lat').text(lat);
      $('#div_lon').text(lon);
    }, null, {enableHighAccuracy: true, timeout: 5000, maximumAge: 1000});
  }
</script>
% if ( $user->{admin} ) {
  <%= link_to Admin => 'status' %><hr />
% }
Name: <%= link_to $user->{first_name} => 'historyuser', {user => $user->{id}} %><br />
%= form_for timeclock => (method => 'POST') => begin
%= hidden_field 'lat' => '', id => 'lat'
%= hidden_field 'lon' => '', id => 'lon'
% if ( my $status = $timeclock->status(session 'id') ) {
  <%= $status->{time_in} %> (<%= $timeclock->duration($status->{duration}) %>)<br />
  %= hidden_field clock => 'out'
  %= submit_button 'Clock out'
% } else {
  Not active <br />
  %= hidden_field clock => 'in'
  %= submit_button 'Clock in'
% }
% end

@@ migrations
-- 1 up
create table if not exists users (
  id         text primary key,
  email      text,
  first_name text,
  last_name  text,
  admin      integer,
  created    timestamptz not null default now()
);
create table if not exists providers (
  id          text,
  provider_id text,
  provider    text,
  created     timestamptz not null default now(),
  PRIMARY KEY (id, provider_id, provider)
);
create table if not exists timeclock (
  id          serial primary key,
  user_id     text,
  time_in     timestamptz,
  time_out    timestamptz,
  time_in_lat text,
  time_in_lon text,
  time_out_lat text,
  time_out_lon text,
  paid        integer
);
CREATE OR REPLACE FUNCTION round_duration(TIMESTAMPTZ, TIMESTAMPTZ) 
RETURNS INTERVAL AS $$ 
  SELECT date_trunc('hour', age(case when $2 is not null then $2 else now() end, $1)) + INTERVAL '15 min' * ROUND(date_part('minute', age(case when $2 is not null then $2 else now() end, $1)) / 15.0) 
$$ LANGUAGE SQL;

-- 1 down
drop table if exists providers;
drop table if exists users;
drop table if exists timeclock;

-- 2 up
alter table users add column disable timestamptz;

-- 2 down
alter table users drop column disable;

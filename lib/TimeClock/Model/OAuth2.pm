package TimeClock::Model::OAuth2;
use Mojo::Base -base;

use UUID::Tiny ':std';

has 'pg';

sub store {
  my $self = shift;
  if ( $#_ == 1 ) {
    my ($id, $provider) = @_;
    my $r = $self->pg->db->query('select id from providers where id = ? and provider = ?', $id, $provider)->hash;
    ref $r ? $r->{id} : undef;
  } elsif ( $#_ > 1 ) {
    my ($id, $provider, $json, $mapped) = @_;
    unless ( $self->pg->db->query('select id from users where id = ?', $id)->rows ) {
      $self->pg->db->query('insert into users (id, email, first_name, last_name) values (?, ?, ?, ?)', $id, $mapped->{email}, $mapped->{first_name}, $mapped->{last_name});
    }
    unless ( $self->pg->db->query('select id from providers where provider_id = ?', $mapped->{id})->rows ) {
      $self->pg->db->query('insert into providers (id, provider_id, provider) values (?, ?, ?)', $id, $mapped->{id}, $provider);
    }
  } else {
    my ($provider_id) = @_;
    my $r = $self->pg->db->query('select id from providers where provider_id = ?', $provider_id)->hash;
    ref $r ? $r->{id} : uuid_to_string(create_uuid(UUID_V4));
  }
}

sub find { shift->pg->db->query('select * from users where id = ?', shift)->hash }

1;

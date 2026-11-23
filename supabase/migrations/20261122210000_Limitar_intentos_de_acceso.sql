begin;

create schema if not exists luxury_auth;
revoke all on schema luxury_auth from public, anon, authenticated;
grant usage on schema luxury_auth to supabase_auth_admin;

create table if not exists luxury_auth.password_login_attempts (
  user_id uuid primary key references auth.users (id) on delete cascade,
  failed_attempts smallint not null check (failed_attempts between 1 and 4),
  locked_until timestamptz,
  check ((failed_attempts = 4) = (locked_until is not null))
);

revoke all on table luxury_auth.password_login_attempts from public, anon, authenticated;
grant select, insert, update, delete on table luxury_auth.password_login_attempts
  to supabase_auth_admin;

-- Register this function as the Password Verification Attempt hook in Supabase Auth.
create or replace function public.luxury_password_verification_attempt(event jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  account_id uuid := (event ->> 'user_id')::uuid;
  password_valid boolean := (event ->> 'valid')::boolean;
  checked_at timestamptz;
  failure_count smallint;
  lock_expiration timestamptz;
begin
  -- Serialize attempts for the same account, including the first attempt.
  perform pg_advisory_xact_lock(hashtextextended(account_id::text, 218380821));
  checked_at := clock_timestamp();

  select attempts.failed_attempts, attempts.locked_until
    into failure_count, lock_expiration
    from luxury_auth.password_login_attempts as attempts
    where attempts.user_id = account_id;

  if lock_expiration > checked_at then
    -- Keep the standard invalid-credentials response for incorrect passwords.
    if password_valid then
      return jsonb_build_object(
        'decision', 'reject',
        'message', 'luxury_login_locked_until:' ||
          ((extract(epoch from lock_expiration) * 1000)::bigint)::text,
        'should_logout_user', false
      );
    end if;
    return jsonb_build_object('decision', 'continue');
  end if;

  if password_valid then
    delete from luxury_auth.password_login_attempts where user_id = account_id;
    return jsonb_build_object('decision', 'continue');
  end if;

  failure_count := case
    when lock_expiration is null then coalesce(failure_count, 0) + 1
    else 1
  end;
  lock_expiration := case
    when failure_count = 4 then checked_at + interval '15 minutes'
  end;

  insert into luxury_auth.password_login_attempts (user_id, failed_attempts, locked_until)
    values (account_id, failure_count, lock_expiration)
    on conflict (user_id) do update
    set failed_attempts = excluded.failed_attempts, locked_until = excluded.locked_until;

  return jsonb_build_object('decision', 'continue');
end;
$$;

grant usage on schema public to supabase_auth_admin;
revoke all on function public.luxury_password_verification_attempt(jsonb)
  from public, anon, authenticated;
grant execute on function public.luxury_password_verification_attempt(jsonb)
  to supabase_auth_admin;

commit;

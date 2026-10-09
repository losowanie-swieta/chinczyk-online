-- Polityczny Chińczyk: darmowy backend online (Supabase)
-- Wklej CAŁOŚĆ do Supabase > SQL Editor > New query > Run.

create table if not exists public.chinczyk_rooms (
  id bigint generated always as identity primary key,
  code text not null unique,
  players jsonb not null default '[]'::jsonb,
  game_state jsonb,
  started boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.chinczyk_rooms enable row level security;
revoke all on public.chinczyk_rooms from anon, authenticated;

create or replace function public.create_chinczyk_room(p_name text)
returns jsonb language plpgsql security definer set search_path = public, extensions
as $$
declare v_code text; v_player text := gen_random_uuid()::text; v_name text;
begin
  v_name := left(trim(coalesce(p_name,'')),24);
  if v_name = '' then raise exception 'Wpisz nick gracza.'; end if;
  loop
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text || v_player),1,6));
    exit when not exists(select 1 from public.chinczyk_rooms where code=v_code);
  end loop;
  insert into public.chinczyk_rooms(code,players)
  values(v_code,jsonb_build_array(jsonb_build_object('id',v_player,'name',v_name,'seat',0,'host',true)));
  return jsonb_build_object('code',v_code,'player_id',v_player,'players',jsonb_build_array(jsonb_build_object('id',v_player,'name',v_name,'seat',0,'host',true)),'started',false,'game_state',null);
end; $$;

create or replace function public.join_chinczyk_room(p_code text,p_name text)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare r public.chinczyk_rooms%rowtype; v_player text := gen_random_uuid()::text; v_name text; v_players jsonb;
begin
  v_name := left(trim(coalesce(p_name,'')),24);
  if v_name = '' then raise exception 'Wpisz nick gracza.'; end if;
  select * into r from public.chinczyk_rooms where code=upper(trim(p_code)) for update;
  if not found then raise exception 'Nie znaleziono pokoju. Sprawdź kod.'; end if;
  if r.started then raise exception 'Ta gra już się rozpoczęła.'; end if;
  if jsonb_array_length(r.players)>=4 then raise exception 'Pokój jest pełny (maksymalnie 4 osoby).'; end if;
  v_players := r.players || jsonb_build_array(jsonb_build_object('id',v_player,'name',v_name,'seat',jsonb_array_length(r.players),'host',false));
  update public.chinczyk_rooms set players=v_players,updated_at=now() where id=r.id;
  return jsonb_build_object('code',r.code,'player_id',v_player,'players',v_players,'started',r.started,'game_state',r.game_state);
end; $$;

create or replace function public.get_chinczyk_room(p_code text)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare r public.chinczyk_rooms%rowtype;
begin
 select * into r from public.chinczyk_rooms where code=upper(trim(p_code));
 if not found then return null; end if;
 return jsonb_build_object('code',r.code,'players',r.players,'started',r.started,'game_state',r.game_state,'updated_at',r.updated_at);
end; $$;

create or replace function public.start_chinczyk_room(p_code text,p_player_id text,p_state jsonb)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare r public.chinczyk_rooms%rowtype;
begin
 select * into r from public.chinczyk_rooms where code=upper(trim(p_code)) for update;
 if not found then raise exception 'Nie znaleziono pokoju.'; end if;
 if not exists(select 1 from jsonb_array_elements(r.players) p where p->>'id'=p_player_id and p->>'host'='true') then raise exception 'Tylko założyciel pokoju może rozpocząć grę.'; end if;
 if jsonb_array_length(r.players)<2 then raise exception 'Do rozpoczęcia gry potrzebne są co najmniej 2 osoby.'; end if;
 update public.chinczyk_rooms set started=true,game_state=p_state,updated_at=now() where id=r.id;
 return jsonb_build_object('ok',true);
end; $$;

create or replace function public.save_chinczyk_state(p_code text,p_player_id text,p_state jsonb)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare r public.chinczyk_rooms%rowtype;
begin
 select * into r from public.chinczyk_rooms where code=upper(trim(p_code)) for update;
 if not found then raise exception 'Pokój już nie istnieje.'; end if;
 if not exists(select 1 from jsonb_array_elements(r.players) p where p->>'id'=p_player_id) then raise exception 'Nie należysz do tego pokoju.'; end if;
 if not r.started then raise exception 'Gra jeszcze się nie rozpoczęła.'; end if;
 update public.chinczyk_rooms set game_state=p_state,updated_at=now() where id=r.id;
 return jsonb_build_object('ok',true);
end; $$;

grant execute on function public.create_chinczyk_room(text) to anon, authenticated;
grant execute on function public.join_chinczyk_room(text,text) to anon, authenticated;
grant execute on function public.get_chinczyk_room(text) to anon, authenticated;
grant execute on function public.start_chinczyk_room(text,text,jsonb) to anon, authenticated;
grant execute on function public.save_chinczyk_state(text,text,jsonb) to anon, authenticated;

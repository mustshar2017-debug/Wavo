-- WAVO Wallet foundation (simulation-ready; no real payment integration)
-- Target Supabase project currently referenced by this repository:
-- jajaujilwhkroboyhenj
-- Apply this migration in Supabase SQL Editor.
--
-- Security model:
-- * Clients can read only their own balances, transactions and requests.
-- * Clients cannot directly change balances or write ledger rows.
-- * Deposits are credited only after an administrator verifies payment.
-- * Withdrawals reserve funds immediately; approval pays them, rejection releases them.
-- * Transfers are same-currency only and atomic.
-- * All monetary changes happen inside SECURITY DEFINER functions.

create extension if not exists pgcrypto;

create table if not exists public.wavo_wallet_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.wavo_wallet_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  currency text not null check (currency in ('SDG','USD')),
  available_balance numeric(20,2) not null default 0 check (available_balance >= 0),
  held_balance numeric(20,2) not null default 0 check (held_balance >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id, currency)
);

create table if not exists public.wavo_wallet_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  request_type text not null check (request_type in ('deposit','withdrawal')),
  currency text not null check (currency in ('SDG','USD')),
  amount numeric(20,2) not null check (amount > 0),
  payment_channel text,
  payment_reference text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  admin_note text,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint wavo_wallet_review_state check (
    (status = 'pending' and reviewed_by is null and reviewed_at is null)
    or (status <> 'pending' and reviewed_by is not null and reviewed_at is not null)
  )
);

create table if not exists public.wavo_wallet_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  currency text not null check (currency in ('SDG','USD')),
  transaction_type text not null check (
    transaction_type in ('deposit','withdrawal','withdrawal_hold','withdrawal_release','transfer_in','transfer_out')
  ),
  amount numeric(20,2) not null check (amount > 0),
  available_after numeric(20,2) not null check (available_after >= 0),
  reference_id uuid not null,
  related_user_id uuid references auth.users(id),
  description text,
  created_at timestamptz not null default now()
);

create index if not exists wavo_wallet_tx_user_created_idx
  on public.wavo_wallet_transactions(user_id, created_at desc);
create index if not exists wavo_wallet_req_user_created_idx
  on public.wavo_wallet_requests(user_id, created_at desc);
create index if not exists wavo_wallet_req_pending_idx
  on public.wavo_wallet_requests(status, created_at) where status = 'pending';

alter table public.wavo_wallet_admins enable row level security;
alter table public.wavo_wallet_accounts enable row level security;
alter table public.wavo_wallet_requests enable row level security;
alter table public.wavo_wallet_transactions enable row level security;

drop policy if exists "wallet users read own accounts" on public.wavo_wallet_accounts;
create policy "wallet users read own accounts" on public.wavo_wallet_accounts
  for select to authenticated using (auth.uid() = user_id);

drop policy if exists "wallet users read own requests" on public.wavo_wallet_requests;
create policy "wallet users read own requests" on public.wavo_wallet_requests
  for select to authenticated using (auth.uid() = user_id);

drop policy if exists "wallet users read own transactions" on public.wavo_wallet_transactions;
create policy "wallet users read own transactions" on public.wavo_wallet_transactions
  for select to authenticated using (auth.uid() = user_id);

-- No client-side INSERT/UPDATE/DELETE policies are intentionally created.
revoke all on public.wavo_wallet_admins from anon, authenticated;
revoke insert, update, delete on public.wavo_wallet_accounts from anon, authenticated;
revoke insert, update, delete on public.wavo_wallet_requests from anon, authenticated;
revoke insert, update, delete on public.wavo_wallet_transactions from anon, authenticated;
grant select on public.wavo_wallet_accounts, public.wavo_wallet_requests, public.wavo_wallet_transactions to authenticated;

-- Make the transaction ledger append-only, including for ordinary SQL updates.
create or replace function public.wavo_wallet_prevent_ledger_mutation()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  raise exception 'WAVO wallet ledger is append-only';
end;
$$;

drop trigger if exists wavo_wallet_transactions_immutable on public.wavo_wallet_transactions;
create trigger wavo_wallet_transactions_immutable
before update or delete on public.wavo_wallet_transactions
for each row execute function public.wavo_wallet_prevent_ledger_mutation();

-- Ensure an account row exists for each supported currency.
create or replace function public.wavo_wallet_ensure_accounts(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.wavo_wallet_accounts(user_id, currency)
  values (p_user_id, 'SDG'), (p_user_id, 'USD')
  on conflict (user_id, currency) do nothing;
end;
$$;
revoke all on function public.wavo_wallet_ensure_accounts(uuid) from public, anon, authenticated;

-- User requests their own wallet initialization; no balance can be supplied by the caller.
create or replace function public.wavo_wallet_initialize()
returns setof public.wavo_wallet_accounts
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  perform public.wavo_wallet_ensure_accounts(auth.uid());
  return query
    select * from public.wavo_wallet_accounts
    where user_id = auth.uid()
    order by currency;
end;
$$;
grant execute on function public.wavo_wallet_initialize() to authenticated;

-- Create a deposit or withdrawal request.
-- Withdrawals reserve funds immediately so the same balance cannot be spent twice.
create or replace function public.wavo_wallet_create_request(
  p_request_type text,
  p_currency text,
  p_amount numeric,
  p_payment_channel text default null,
  p_payment_reference text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_request_id uuid := gen_random_uuid();
  v_available numeric(20,2);
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_request_type not in ('deposit','withdrawal') then raise exception 'Invalid request type'; end if;
  if p_currency not in ('SDG','USD') then raise exception 'Unsupported currency'; end if;
  if p_amount is null or p_amount <= 0 or p_amount <> round(p_amount, 2) then
    raise exception 'Amount must be positive and limited to two decimal places';
  end if;
  if coalesce(length(trim(p_payment_channel)),0) > 80
     or coalesce(length(trim(p_payment_reference)),0) > 160 then
    raise exception 'Payment details are too long';
  end if;

  perform public.wavo_wallet_ensure_accounts(v_user);

  if p_request_type = 'withdrawal' then
    update public.wavo_wallet_accounts
      set available_balance = available_balance - p_amount,
          held_balance = held_balance + p_amount,
          updated_at = now()
      where user_id = v_user and currency = p_currency
        and available_balance >= p_amount
      returning available_balance into v_available;
    if not found then raise exception 'Insufficient available balance'; end if;
  end if;

  insert into public.wavo_wallet_requests(
    id, user_id, request_type, currency, amount, payment_channel, payment_reference
  ) values (
    v_request_id, v_user, p_request_type, p_currency, p_amount,
    nullif(trim(p_payment_channel),''), nullif(trim(p_payment_reference),'')
  );

  if p_request_type = 'withdrawal' then
    insert into public.wavo_wallet_transactions(
      user_id, currency, transaction_type, amount, available_after, reference_id, description
    ) values (
      v_user, p_currency, 'withdrawal_hold', p_amount, v_available, v_request_id,
      'Withdrawal request reserved; awaiting review'
    );
  end if;

  return v_request_id;
end;
$$;
grant execute on function public.wavo_wallet_create_request(text,text,numeric,text,text) to authenticated;

-- Same-currency transfer. Both account rows are locked and changed in one transaction.
create or replace function public.wavo_wallet_transfer(
  p_recipient uuid,
  p_currency text,
  p_amount numeric,
  p_description text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_sender uuid := auth.uid();
  v_ref uuid := gen_random_uuid();
  v_sender_after numeric(20,2);
  v_recipient_after numeric(20,2);
begin
  if v_sender is null then raise exception 'Authentication required'; end if;
  if p_recipient is null or p_recipient = v_sender then raise exception 'Invalid recipient'; end if;
  if p_currency not in ('SDG','USD') then raise exception 'Unsupported currency'; end if;
  if p_amount is null or p_amount <= 0 or p_amount <> round(p_amount, 2) then
    raise exception 'Amount must be positive and limited to two decimal places';
  end if;
  if coalesce(length(trim(p_description)),0) > 160 then raise exception 'Description is too long'; end if;
  if not exists (select 1 from auth.users where id = p_recipient) then
    raise exception 'Recipient account not found';
  end if;

  perform public.wavo_wallet_ensure_accounts(v_sender);
  perform public.wavo_wallet_ensure_accounts(p_recipient);

  perform 1 from public.wavo_wallet_accounts
    where user_id in (v_sender, p_recipient) and currency = p_currency
    order by user_id
    for update;

  update public.wavo_wallet_accounts
    set available_balance = available_balance - p_amount, updated_at = now()
    where user_id = v_sender and currency = p_currency
      and available_balance >= p_amount
    returning available_balance into v_sender_after;
  if not found then raise exception 'Insufficient available balance'; end if;

  update public.wavo_wallet_accounts
    set available_balance = available_balance + p_amount, updated_at = now()
    where user_id = p_recipient and currency = p_currency
    returning available_balance into v_recipient_after;

  insert into public.wavo_wallet_transactions(
    user_id, currency, transaction_type, amount, available_after, reference_id, related_user_id, description
  ) values
    (v_sender, p_currency, 'transfer_out', p_amount, v_sender_after, v_ref, p_recipient,
     coalesce(nullif(trim(p_description),''),'WAVO wallet transfer')),
    (p_recipient, p_currency, 'transfer_in', p_amount, v_recipient_after, v_ref, v_sender,
     coalesce(nullif(trim(p_description),''),'WAVO wallet transfer'));

  return v_ref;
end;
$$;
grant execute on function public.wavo_wallet_transfer(uuid,text,numeric,text) to authenticated;

-- Admin-only review. A deposit is credited only after verification outside WAVO.
-- An approved withdrawal consumes held funds; a rejected one releases them.
create or replace function public.wavo_wallet_review_request(
  p_request_id uuid,
  p_decision text,
  p_admin_note text default null
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin uuid := auth.uid();
  v_req public.wavo_wallet_requests%rowtype;
  v_available numeric(20,2);
begin
  if v_admin is null or not exists (
    select 1 from public.wavo_wallet_admins where user_id = v_admin
  ) then raise exception 'Administrator access required'; end if;
  if p_decision not in ('approved','rejected') then raise exception 'Invalid decision'; end if;
  if coalesce(length(trim(p_admin_note)),0) > 300 then raise exception 'Admin note is too long'; end if;

  select * into v_req from public.wavo_wallet_requests
    where id = p_request_id for update;
  if not found then raise exception 'Request not found'; end if;
  if v_req.status <> 'pending' then raise exception 'Request has already been reviewed'; end if;

  perform public.wavo_wallet_ensure_accounts(v_req.user_id);

  if v_req.request_type = 'deposit' and p_decision = 'approved' then
    update public.wavo_wallet_accounts
      set available_balance = available_balance + v_req.amount, updated_at = now()
      where user_id = v_req.user_id and currency = v_req.currency
      returning available_balance into v_available;
    insert into public.wavo_wallet_transactions(
      user_id, currency, transaction_type, amount, available_after, reference_id, description
    ) values (
      v_req.user_id, v_req.currency, 'deposit', v_req.amount, v_available, v_req.id,
      'Deposit approved after manual payment verification'
    );
  elsif v_req.request_type = 'withdrawal' and p_decision = 'approved' then
    update public.wavo_wallet_accounts
      set held_balance = held_balance - v_req.amount, updated_at = now()
      where user_id = v_req.user_id and currency = v_req.currency
        and held_balance >= v_req.amount
      returning available_balance into v_available;
    if not found then raise exception 'Reserved withdrawal balance is inconsistent'; end if;
    insert into public.wavo_wallet_transactions(
      user_id, currency, transaction_type, amount, available_after, reference_id, description
    ) values (
      v_req.user_id, v_req.currency, 'withdrawal', v_req.amount, v_available, v_req.id,
      'Withdrawal approved; payout must be completed by the operator'
    );
  elsif v_req.request_type = 'withdrawal' and p_decision = 'rejected' then
    update public.wavo_wallet_accounts
      set available_balance = available_balance + v_req.amount,
          held_balance = held_balance - v_req.amount,
          updated_at = now()
      where user_id = v_req.user_id and currency = v_req.currency
        and held_balance >= v_req.amount
      returning available_balance into v_available;
    if not found then raise exception 'Reserved withdrawal balance is inconsistent'; end if;
    insert into public.wavo_wallet_transactions(
      user_id, currency, transaction_type, amount, available_after, reference_id, description
    ) values (
      v_req.user_id, v_req.currency, 'withdrawal_release', v_req.amount, v_available, v_req.id,
      'Rejected withdrawal released back to available balance'
    );
  end if;

  update public.wavo_wallet_requests
    set status = p_decision, admin_note = nullif(trim(p_admin_note),''),
        reviewed_by = v_admin, reviewed_at = now()
    where id = v_req.id;

  return true;
end;
$$;
grant execute on function public.wavo_wallet_review_request(uuid,text,text) to authenticated;

-- Bootstrap the first wallet administrator manually in Supabase SQL Editor
-- after confirming the intended user's auth.users.id:
-- insert into public.wavo_wallet_admins(user_id) values ('YOUR-AUTH-USER-UUID');
--
-- IMPORTANT: This migration creates a simulation-ready internal ledger only.
-- It does not connect to banks, mobile-money providers, or real-money settlement.

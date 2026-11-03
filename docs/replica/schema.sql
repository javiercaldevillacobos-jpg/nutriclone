-- NutriClone: esquema Postgres (Supabase). Migración 0001.
-- Espejo en la nube de los modelos SwiftData locales. La app funciona offline;
-- este esquema solo se usa cuando el usuario activa la cuenta/sincronización.
-- Acceso: Row Level Security en todas las tablas de usuario (auth.uid()).
-- Tiempos en timestamptz (UTC). Días de registro como date en la zona del usuario.

create extension if not exists pg_trgm;
create extension if not exists unaccent;

-- Función de updated_at
create or replace function set_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

-- ---------------------------------------------------------------- perfiles
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  sex text check (sex in ('male','female')),
  birthdate date,
  height_cm numeric(5,1) check (height_cm between 100 and 250),
  units text not null default 'metric' check (units in ('metric','imperial')),
  locale text not null default 'es-ES',
  timezone text not null default 'Europe/Madrid',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  goal_type text not null check (goal_type in ('lose','maintain','gain')),
  target_weight_kg numeric(5,1),
  pace_kg_week numeric(3,2) not null default 0.5 check (pace_kg_week between 0 and 1.5),
  activity_level text not null check (activity_level in ('sedentary','light','moderate','active','very_active')),
  diet_type text not null default 'balanced'
    check (diet_type in ('balanced','high_protein','low_carb','keto','low_fat')),
  kcal int not null check (kcal between 1000 and 6000),
  protein_g int not null, carbs_g int not null, fat_g int not null,
  water_ml int not null default 2000,
  meals_per_day smallint not null default 4 check (meals_per_day between 3 and 6),
  dynamic_adjust boolean not null default true,
  exclusions text[] not null default '{}',          -- alergias / no me gusta
  active_from date not null default current_date,  -- historial: la meta vigente es la más reciente
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on goals (user_id, active_from desc);

-- ---------------------------------------------------------------- alimentos
-- Catálogo compartido (source != 'user', user_id null) + alimentos propios.
create table foods (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,   -- null = catálogo público
  source text not null check (source in ('usda','off','curated','user','ai')),
  source_ref text,                                           -- fdcId / código OFF
  name text not null,
  brand text,
  barcode text,
  locale text not null default 'es',
  -- valores por 100 g (o 100 ml)
  kcal numeric(6,1) not null check (kcal >= 0),
  protein_g numeric(5,1) not null default 0,
  carbs_g numeric(5,1) not null default 0,
  fat_g numeric(5,1) not null default 0,
  fiber_g numeric(5,1), sugar_g numeric(5,1), sat_fat_g numeric(5,1), sodium_mg numeric(7,1),
  micros jsonb not null default '{}',                         -- resto de los 20+ nutrientes
  servings jsonb not null default '[]',                       -- [{"label":"1 unidad","grams":120}]
  verified boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_food_has_owner check (source <> 'user' or user_id is not null)
);
create unique index foods_barcode_public on foods (barcode) where barcode is not null and user_id is null;
create index foods_name_trgm on foods using gin (lower(name) gin_trgm_ops);
create index on foods (user_id);

create table recipes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,   -- null = recetas del sistema
  name text not null,
  servings smallint not null default 1 check (servings > 0),
  prep_minutes smallint,
  steps text[] not null default '{}',
  image_path text,
  tags text[] not null default '{}',                          -- diet types, meal slot hints
  meal_slots text[] not null default '{}',                    -- breakfast, lunch, dinner, snack
  -- totales cacheados por ración (recalculados por trigger/app)
  kcal numeric(6,1) not null default 0,
  protein_g numeric(5,1) not null default 0,
  carbs_g numeric(5,1) not null default 0,
  fat_g numeric(5,1) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on recipes (user_id);
create index on recipes using gin (tags);

create table recipe_ingredients (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references recipes(id) on delete cascade,
  food_id uuid not null references foods(id) on delete restrict,
  grams numeric(7,1) not null check (grams > 0),
  label text,                                                 -- "2 huevos"
  position smallint not null default 0
);
create index on recipe_ingredients (recipe_id);
create index on recipe_ingredients (food_id);

create table favorites (
  user_id uuid not null references auth.users(id) on delete cascade,
  food_id uuid references foods(id) on delete cascade,
  recipe_id uuid references recipes(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint one_target check ((food_id is null) <> (recipe_id is null))
);
create unique index on favorites (user_id, food_id) where food_id is not null;
create unique index on favorites (user_id, recipe_id) where recipe_id is not null;

-- ---------------------------------------------------------------- diario
create table food_logs (
  id uuid primary key default gen_random_uuid(),   -- generado en el cliente (idempotente)
  user_id uuid not null references auth.users(id) on delete cascade,
  log_date date not null,                          -- día local del usuario
  meal_slot text not null check (meal_slot in ('breakfast','morning_snack','lunch','afternoon_snack','dinner','extra')),
  food_id uuid references foods(id) on delete set null,
  recipe_id uuid references recipes(id) on delete set null,
  name text not null,                              -- snapshot: el log sobrevive al borrado del alimento
  grams numeric(7,1) not null check (grams > 0),
  serving_label text,
  kcal numeric(6,1) not null, protein_g numeric(5,1) not null,
  carbs_g numeric(5,1) not null, fat_g numeric(5,1) not null,
  method text not null default 'search'
    check (method in ('search','barcode','photo','voice','text','plan','quick')),
  logged_at timestamptz not null default now(),
  deleted_at timestamptz,                          -- borrado lógico para sync
  updated_at timestamptz not null default now()
);
create index on food_logs (user_id, log_date);
create index on food_logs (user_id, updated_at);

create table water_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  log_date date not null,
  ml int not null check (ml > 0 and ml <= 3000),
  logged_at timestamptz not null default now(),
  deleted_at timestamptz,
  updated_at timestamptz not null default now()
);
create index on water_logs (user_id, log_date);

-- ---------------------------------------------------------------- plan
create table meal_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  start_date date not null,
  days smallint not null default 7 check (days between 1 and 14),
  goal_id uuid references goals(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on meal_plans (user_id, start_date desc);

create table plan_items (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references meal_plans(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_date date not null,
  meal_slot text not null,
  recipe_id uuid not null references recipes(id) on delete restrict,
  servings numeric(4,2) not null default 1 check (servings > 0),
  eaten_log_id uuid references food_logs(id) on delete set null,
  updated_at timestamptz not null default now(),
  unique (plan_id, plan_date, meal_slot, recipe_id)
);
create index on plan_items (plan_id, plan_date);
create index on plan_items (user_id);

create table shopping_items (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references meal_plans(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  food_id uuid references foods(id) on delete set null,
  name text not null,
  grams numeric(8,1),
  category text not null default 'other',
  checked boolean not null default false,
  updated_at timestamptz not null default now()
);
create index on shopping_items (plan_id);

-- ---------------------------------------------------------------- progreso
create table body_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  entry_date date not null,
  weight_kg numeric(5,1) check (weight_kg between 25 and 400),
  body_fat_pct numeric(4,1) check (body_fat_pct between 2 and 70),
  waist_cm numeric(5,1), hip_cm numeric(5,1), neck_cm numeric(5,1),
  arm_cm numeric(5,1), thigh_cm numeric(5,1), chest_cm numeric(5,1),
  source text not null default 'manual' check (source in ('manual','healthkit')),
  deleted_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (user_id, entry_date, source)
);
create index on body_entries (user_id, entry_date);

create table progress_photos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  taken_on date not null,
  pose text not null default 'front' check (pose in ('front','side','back')),
  storage_path text not null,                     -- bucket privado progress-photos/{user_id}/...
  created_at timestamptz not null default now()
);
create index on progress_photos (user_id, taken_on);

create table fast_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  protocol text not null,                         -- '16:8', '18:6', '20:4', 'custom'
  target_hours numeric(4,1) not null check (target_hours between 1 and 72),
  started_at timestamptz not null,
  ended_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint ends_after_start check (ended_at is null or ended_at > started_at)
);
-- un solo ayuno abierto por usuario
create unique index one_open_fast on fast_sessions (user_id) where ended_at is null;

create table activity_days (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  active_kcal int not null default 0,
  steps int not null default 0,
  source text not null default 'healthkit',
  updated_at timestamptz not null default now(),
  primary key (user_id, day)
);

-- ---------------------------------------------------------------- coach y cuotas
create table coach_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('user','assistant')),
  content text not null,
  created_at timestamptz not null default now()
);
create index on coach_messages (user_id, created_at);

create table ai_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  kind text not null check (kind in ('parse','photo','coach','plan')),
  count int not null default 0,
  primary key (user_id, day, kind)
);

-- ---------------------------------------------------------------- suscripción
create table subscriptions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  product_id text not null,
  original_transaction_id text not null unique,
  expires_at timestamptz,
  status text not null check (status in ('active','in_grace','expired','revoked','trial')),
  environment text not null default 'Production' check (environment in ('Production','Sandbox')),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------- triggers updated_at
do $$ declare t text; begin
  foreach t in array array['profiles','goals','foods','recipes','food_logs','water_logs',
    'meal_plans','plan_items','shopping_items','body_entries','fast_sessions','activity_days','subscriptions']
  loop execute format('create trigger %I_updated before update on %I for each row execute function set_updated_at()', t, t);
  end loop; end $$;

-- ---------------------------------------------------------------- RLS
alter table profiles enable row level security;
create policy own on profiles for all using (id = auth.uid()) with check (id = auth.uid());

do $$ declare t text; begin
  foreach t in array array['goals','favorites','food_logs','water_logs','meal_plans','plan_items',
    'shopping_items','body_entries','progress_photos','fast_sessions','activity_days','coach_messages']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy own on %I for all using (user_id = auth.uid()) with check (user_id = auth.uid())', t);
  end loop; end $$;

-- catálogo: todos leen lo público y lo suyo; solo escriben lo suyo
alter table foods enable row level security;
create policy read_foods on foods for select using (user_id is null or user_id = auth.uid());
create policy write_own_foods on foods for all using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table recipes enable row level security;
create policy read_recipes on recipes for select using (user_id is null or user_id = auth.uid());
create policy write_own_recipes on recipes for all using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table recipe_ingredients enable row level security;
create policy read_ingredients on recipe_ingredients for select
  using (exists (select 1 from recipes r where r.id = recipe_id and (r.user_id is null or r.user_id = auth.uid())));
create policy write_ingredients on recipe_ingredients for all
  using (exists (select 1 from recipes r where r.id = recipe_id and r.user_id = auth.uid()))
  with check (exists (select 1 from recipes r where r.id = recipe_id and r.user_id = auth.uid()));

-- ai_usage y subscriptions: solo lectura para el usuario; escriben las Edge Functions con service role
alter table ai_usage enable row level security;
create policy read_own on ai_usage for select using (user_id = auth.uid());
alter table subscriptions enable row level security;
create policy read_own on subscriptions for select using (user_id = auth.uid());

-- ---------------------------------------------------------------- búsqueda
create or replace function search_foods(q text, lim int default 30)
returns setof foods language sql stable as $$
  select * from foods
  where (user_id is null or user_id = auth.uid())
    and (lower(name) % lower(q) or lower(name) like lower(q) || '%')
  order by (user_id = auth.uid()) desc nulls last, verified desc,
           similarity(lower(name), lower(q)) desc
  limit lim;
$$;

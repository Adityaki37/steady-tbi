import { PGlite } from '@electric-sql/pglite';
import { readFile, writeFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';

// Real PostgreSQL SQL/RLS execution in WASM. Auth and Storage tables are minimal
// test doubles, not the Supabase HTTP/Auth/Storage services or a deployed project.
const db = new PGlite();
let assertions = 0;
const check = (value, expected, label) => { assert.deepEqual(value, expected, label); assertions++; };
const users = {
  survivor: '00000000-0000-4000-8000-000000000001',
  caregiver: '00000000-0000-4000-8000-000000000002',
  clinician: '00000000-0000-4000-8000-000000000003',
  outsider: '00000000-0000-4000-8000-000000000004',
  unconfirmed: '00000000-0000-4000-8000-000000000005'
};
async function as(who, sql, params = []) {
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claim.sub', $1, false)", [users[who] ?? '']);
  await db.exec('set role ' + (who === 'anon' ? 'anon' : 'authenticated'));
  try { return await db.query(sql, params); } finally { await db.exec('reset role'); }
}
async function denied(who, sql, params = []) {
  let rejected = false;
  try { await as(who, sql, params); } catch (error) { rejected = error.code === '42501'; }
  check(rejected, true, `${who} must be denied: ${sql.slice(0,80)}`);
}
async function rejects(who, sql, params = []) {
  let rejected = false; try { await as(who, sql, params); } catch { rejected = true; }
  check(rejected, true, 'invalid call must fail');
}
const kinds = ['symptoms','observations','notes','attachments'];
const id = (i) => `10000000-0000-4000-8000-${String(i).padStart(12,'0')}`;
let sequence = 0;
try {
  await db.exec(`
    create role anon nologin;
    create role authenticated nologin;
    create schema auth; create schema storage;
    create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);
    create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
    grant usage on schema auth to anon,authenticated;
    grant execute on function auth.uid() to anon,authenticated;
    create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text references storage.buckets(id),name text,owner_id text);
    alter table storage.objects enable row level security;
    grant usage on schema storage to authenticated;
    grant select,insert,update,delete on storage.objects to authenticated;
  `);
  for (const [name, uuid] of Object.entries(users)) await db.query('insert into auth.users values ($1,$2,$3)', [uuid, `${name}@example.test`, name === 'unconfirmed' ? null : '2026-10-28T12:00:00Z']);
  const schema = await readFile(new URL('../backend/schema.sql', import.meta.url), 'utf8');
  await db.exec(schema);
  console.log('PASS: migration applies in PostgreSQL (PGlite)');
  const circle = (await as('survivor', "select public.create_circle('Fictional Alex') as id")).rows[0].id;
  const other = (await as('outsider', "select public.create_circle('Other fictional circle') as id")).rows[0].id;
  for (const role of ['caregiver','clinician']) {
    const token = (await as('survivor', 'select public.invite_member($1,$2,$3) as token', [circle, `${role}@example.test`, role])).rows[0].token;
    await denied('outsider', 'select public.accept_invite($1)', [token]);
    check((await as(role, 'select public.accept_invite($1) as id', [token])).rows[0].id, circle, 'matching confirmed recipient accepts');
    await denied(role, 'select public.accept_invite($1)', [token]);
  }
  await denied('anon', "select public.create_circle('No account')");
  await denied('caregiver', 'select public.invite_member($1,$2,$3)', [circle, 'outsider@example.test', 'clinician']);
  await denied('caregiver', 'insert into public.circle_members values($1,$2,$3)', [circle, users.outsider, 'clinician']);
  check((await as('caregiver','select * from public.circle_permissions where circle_id=$1',[circle])).rows.length,0,'shared role cannot read owner control rows');
  check((await as('outsider','select * from public.circles where id=$1',[circle])).rows.length,0,'cross-circle isolation');
  const tokenUnconfirmed = (await as('survivor','select public.invite_member($1,$2,$3) as token',[circle,'unconfirmed@example.test','caregiver'])).rows[0].token;
  await denied('unconfirmed','select public.accept_invite($1)',[tokenUnconfirmed]);
  const invitationID = (await db.query("select id from public.circle_invitations where recipient_email='unconfirmed@example.test'")).rows[0].id;
  await as('survivor','select public.revoke_invite($1)',[invitationID]);
  await db.query('update auth.users set email_confirmed_at=now() where id=$1',[users.unconfirmed]);
  await denied('unconfirmed','select public.accept_invite($1)',[tokenUnconfirmed]);
  const expiredToken=(await as('survivor','select public.invite_member($1,$2,$3) as token',[circle,'unconfirmed@example.test','clinician'])).rows[0].token;
  await db.exec("update public.circle_invitations set expires_at=now()-interval '1 hour' where recipient_email='unconfirmed@example.test'");
  await denied('unconfirmed','select public.accept_invite($1)',[expiredToken]);

  // Test defaults before changing them.
  const symptomID=id(++sequence);
  await as('survivor',"insert into public.records(id,circle_id,kind,author_id,title) values($1,$2,'symptoms',$3,'Fictional symptom')",[symptomID,circle,users.survivor]);
  check((await as('caregiver','select * from public.records where circle_id=$1',[circle])).rows.length,0,'caregiver cannot see symptom history');
  await as('caregiver',"insert into public.records(circle_id,kind,author_id,title) values($1,'observations',$2,'Fictional add without symptom read')",[circle,users.caregiver]);
  check((await as('clinician','select * from public.records where id=$1',[symptomID])).rows.length,1,'clinician default symptom read');
  await denied('caregiver',"insert into public.records(circle_id,kind,author_id,title) values($1,'notes',$2,'Denied')",[circle,users.caregiver]);

  // Execute all 16 CRUD combinations, for both shared roles and every kind.
  let combinations=0;
  for (const role of ['caregiver','clinician']) for (const kind of kinds) for (let bits=0;bits<16;bits++) {
    const read=!!(bits&1), add=!!(bits&2), edit=read&&!!(bits&4), del=read&&!!(bits&8);
    await as('survivor','update public.circle_permissions set can_read=$1,can_add=$2,can_edit=$3,can_delete=$4 where circle_id=$5 and role=$6 and kind=$7',[read,add,!!(bits&4),!!(bits&8),circle,role,kind]);
    for (const [action,expected] of Object.entries({read,add,edit,delete:del})) check((await as(role,'select private.allowed($1,$2,$3) as allowed',[circle,kind,action])).rows[0].allowed,expected,`${role}/${kind}/${bits}/${action}`);
    const recordID=id(++sequence);
    const path=kind==='attachments' ? `${circle}/${recordID}.png` : null;
    await as('survivor', 'insert into public.records(id,circle_id,kind,author_id,title,file_path,file_name) values($1,$2,$3,$4,$5,$6,$7)',[recordID,circle,kind,users.survivor,'Fictional matrix test',path,path?'fictional.png':null]);
    check((await as(role,'select * from public.records where id=$1',[recordID])).rows.length,read?1:0,'SELECT matches grant');
    const addSQL='insert into public.records(circle_id,kind,author_id,title,file_path,file_name) values($1,$2,$3,$4,$5,$6)';
    const params=[circle,kind,users[role],'Fictional contribution',path,path?'fictional.png':null];
    if (add) { await as(role,addSQL,params); assertions++; } else await denied(role,addSQL,params);
    check((await as(role,"update public.records set body='Fictional edit' where id=$1 returning id",[recordID])).rows.length,edit?1:0,'UPDATE matches read+edit');
    check((await as(role,'delete from public.records where id=$1 returning id',[recordID])).rows.length,del?1:0,'DELETE matches read+delete');
    combinations++;
  }
  check(combinations,128,'all permission combinations executed');
  // Add-only records must work without returning private rows.
  await as('survivor',"update public.circle_permissions set can_read=false,can_add=true where circle_id=$1 and role='caregiver'",[circle]);
  await as('caregiver',"insert into public.records(circle_id,kind,author_id,title) values($1,'observations',$2,'Private history contribution')",[circle,users.caregiver]);
  check((await as('caregiver','select * from public.records where circle_id=$1',[circle])).rows.length,0,'no history or counts leaked when all reads off');
  await denied('caregiver',"insert into public.records(circle_id,kind,author_id,title) values($1,'observations',$2,'Spoofed author')",[circle,users.survivor]);
  await denied('caregiver',"insert into public.records(circle_id,kind,author_id,title) values($1,'observations',$2,'Other circle')",[other,users.caregiver]);
  await rejects('survivor',"update public.records set circle_id=$1 where id=$2",[other,symptomID]);
  await rejects('survivor',"update public.records set author_id=$1 where id=$2",[users.caregiver,symptomID]);
  await rejects('survivor',"insert into public.records(circle_id,kind,author_id,title,severity) values($1,'symptoms',$2,'Invalid rating',6)",[circle,users.survivor]);
  // Storage policies mirror attachment grants and cannot be bypassed by object names.
  const storagePath=`${circle}/${id(++sequence)}.png`;
  await as('caregiver','insert into storage.objects(bucket_id,name,owner_id) values($1,$2,$3)',['steady-fictional',storagePath,users.caregiver]);
  check((await as('caregiver','select * from storage.objects where name=$1',[storagePath])).rows.length,0,'add-only uploader cannot read files');
  check((await as('survivor','select * from storage.objects where name=$1',[storagePath])).rows.length,1,'survivor can read uploaded object');
  await denied('outsider','insert into storage.objects(bucket_id,name,owner_id) values($1,$2,$3)',['steady-fictional',storagePath,users.outsider]);
  await denied('caregiver','insert into storage.objects(bucket_id,name,owner_id) values($1,$2,$3)',['steady-fictional','../other.png',users.caregiver]);
  await denied('caregiver','insert into storage.objects(bucket_id,name,owner_id) values($1,$2,$3)',['steady-fictional',storagePath,users.survivor]);
  await as('caregiver',"insert into public.check_ins(circle_id,sender_id) values($1,$2)",[circle,users.caregiver]);
  await denied('clinician',"insert into public.check_ins(circle_id,sender_id) values($1,$2)",[circle,users.clinician]);
  await denied('caregiver',"insert into public.check_ins(circle_id,sender_id) values($1,$2)",[other,users.caregiver]);
  check((await as('survivor','select * from public.check_ins where circle_id=$1',[circle])).rows.length,1,'survivor receives shared check-in');
  check((await as('clinician','select * from public.check_ins where circle_id=$1',[circle])).rows.length,0,'clinician cannot read check-ins');
  await as('survivor','delete from public.circle_members where circle_id=$1 and user_id=$2',[circle,users.caregiver]);
  await denied('caregiver',"insert into public.records(circle_id,kind,author_id,title) values($1,'observations',$2,'Revoked')",[circle,users.caregiver]);
  await denied('caregiver',"insert into public.check_ins(circle_id,sender_id) values($1,$2)",[circle,users.caregiver]);
  check((await as('caregiver','select * from storage.objects where name=$1',[storagePath])).rows.length,0,'membership revocation removes file access');
  const exposed=(await db.query("select tablename,rowsecurity from pg_tables where schemaname='public' order by tablename")).rows;
  check(exposed.every(table=>table.rowsecurity),true,'RLS enabled on every public table');
  const report={engine:'PGlite 0.5.13 (PostgreSQL WASM)',assertions,permissionCombinations:combinations,status:'PASS',schemaSHA256:createHash('sha256').update(schema).digest('hex'),limitations:['Supabase Auth and Storage service tables are test doubles','No Xcode compile, Swift test execution, hosted service or iPhone run performed']};
  await writeFile(new URL('../Validation/backend-results.json',import.meta.url),JSON.stringify(report,null,2)+'\n');
  console.log(`PASS: ${assertions} assertions; ${combinations} permission combinations, invitations, cross-circle isolation, storage gates, check-ins and revocation`);
} catch (error) {
  console.error('FAIL:', error.message, error.code ?? '', error.query ?? '');
  process.exitCode=1;
} finally { await db.close(); }

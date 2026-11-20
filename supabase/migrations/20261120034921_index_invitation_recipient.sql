-- Covers invitation recipient lookups and the recipient-user foreign key.
create index if not exists circle_invitations_recipient_user_id_idx
  on public.circle_invitations (recipient_user_id);

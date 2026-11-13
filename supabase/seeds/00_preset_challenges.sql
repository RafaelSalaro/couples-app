-- The 5 free preset challenges (docs/03-feature-spec.md §8). Safe to re-run.
-- The premium library is in 10_challenge_library.sql (owned by the content lane).
insert into public.challenges (relationship_type, title, description, minutes, category, is_shared, tier)
values
  ('romantic', 'Phone-free dinner together', 'Share a meal with both phones out of reach.', 20, 'together', true, 'free'),
  ('romantic', 'Walk together without phones', 'Take a walk, just the two of you. Leave the phones at home or in a pocket.', 20, 'movement', true, 'free'),
  ('romantic', 'Make your partner laugh today', 'A joke, a silly dance, an old story. Anything that gets a real laugh.', 10, 'kindness', false, 'free'),
  ('romantic', 'Cook something together', 'Pick a recipe and make it side by side.', 25, 'together', true, 'free'),
  ('romantic', 'Write your partner a note', 'A few handwritten lines left where they will find them.', 10, 'kindness', false, 'free')
on conflict (relationship_type, title) where pair_id is null do nothing;

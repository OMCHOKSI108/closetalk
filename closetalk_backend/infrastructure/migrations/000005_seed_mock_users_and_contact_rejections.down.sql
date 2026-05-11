ALTER TABLE contacts DROP CONSTRAINT IF EXISTS contacts_status_check;
ALTER TABLE contacts ADD CONSTRAINT contacts_status_check
    CHECK (status IN ('pending','sent','accepted','blocked'));

DELETE FROM users
WHERE username IN (
    'hitenkatariya',
    'omchoksi',
    'Choksi108',
    'aaryapatel',
    'vivaanmehta',
    'kiarashah',
    'devrajjoshi',
    'nishakapoor',
    'arjunrao',
    'mira_iyer',
    'kabirtrivedi',
    'riya_sen',
    'adviknair',
    'tanishqdesai',
    'ishamalhotra'
)
  AND oauth_provider = 'mock';

DELETE FROM conversations c
WHERE c.type = 'direct'
  AND NOT EXISTS (
      SELECT 1 FROM conversation_participants cp
      WHERE cp.conversation_id = c.id
  );

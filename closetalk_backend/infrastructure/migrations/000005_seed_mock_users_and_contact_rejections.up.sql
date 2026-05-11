INSERT INTO users (email, display_name, username, bio, oauth_provider, oauth_id)
VALUES
    ('hitenkatariya@mock.closetalk.local', 'Hiten Katariya', 'hitenkatariya', 'Mock contact for development', 'mock', 'mock:hitenkatariya'),
    ('omchoksi@mock.closetalk.local', 'Om Choksi', 'omchoksi', 'Mock contact for development', 'mock', 'mock:omchoksi'),
    ('choksi108@mock.closetalk.local', 'Choksi108', 'Choksi108', 'Mock contact for development', 'mock', 'mock:Choksi108')
ON CONFLICT (username) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    bio = EXCLUDED.bio,
    updated_at = now();

ALTER TABLE contacts DROP CONSTRAINT IF EXISTS contacts_status_check;
ALTER TABLE contacts ADD CONSTRAINT contacts_status_check
    CHECK (status IN ('pending','sent','accepted','blocked','rejected'));

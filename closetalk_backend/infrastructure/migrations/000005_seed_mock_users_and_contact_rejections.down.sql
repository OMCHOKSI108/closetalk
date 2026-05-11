ALTER TABLE contacts DROP CONSTRAINT IF EXISTS contacts_status_check;
ALTER TABLE contacts ADD CONSTRAINT contacts_status_check
    CHECK (status IN ('pending','sent','accepted','blocked'));

DELETE FROM users
WHERE username IN ('hitenkatariya', 'omchoksi', 'Choksi108')
  AND oauth_provider = 'mock';

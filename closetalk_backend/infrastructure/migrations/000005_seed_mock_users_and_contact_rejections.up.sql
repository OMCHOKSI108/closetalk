INSERT INTO users (email, display_name, username, bio, oauth_provider, oauth_id)
VALUES
    ('hitenkatariya@mock.closetalk.local', 'Hiten Katariya', 'hitenkatariya', 'Mock contact for development', 'mock', 'mock:hitenkatariya'),
    ('omchoksi@mock.closetalk.local', 'Om Choksi', 'omchoksi', 'Mock contact for development', 'mock', 'mock:omchoksi'),
    ('choksi108@mock.closetalk.local', 'Choksi108', 'Choksi108', 'Mock contact for development', 'mock', 'mock:Choksi108'),
    ('aaryapatel@mock.closetalk.local', 'Aarya Patel', 'aaryapatel', 'Mock contact for development', 'mock', 'mock:aaryapatel'),
    ('vivaanmehta@mock.closetalk.local', 'Vivaan Mehta', 'vivaanmehta', 'Mock contact for development', 'mock', 'mock:vivaanmehta'),
    ('kiarashah@mock.closetalk.local', 'Kiara Shah', 'kiarashah', 'Mock contact for development', 'mock', 'mock:kiarashah'),
    ('devrajjoshi@mock.closetalk.local', 'Devraj Joshi', 'devrajjoshi', 'Mock contact for development', 'mock', 'mock:devrajjoshi'),
    ('nishakapoor@mock.closetalk.local', 'Nisha Kapoor', 'nishakapoor', 'Mock contact for development', 'mock', 'mock:nishakapoor'),
    ('arjunrao@mock.closetalk.local', 'Arjun Rao', 'arjunrao', 'Mock contact for development', 'mock', 'mock:arjunrao'),
    ('miraiyer@mock.closetalk.local', 'Mira Iyer', 'mira_iyer', 'Mock contact for development', 'mock', 'mock:mira_iyer'),
    ('kabirtrivedi@mock.closetalk.local', 'Kabir Trivedi', 'kabirtrivedi', 'Mock contact for development', 'mock', 'mock:kabirtrivedi'),
    ('riyasen@mock.closetalk.local', 'Riya Sen', 'riya_sen', 'Mock contact for development', 'mock', 'mock:riya_sen'),
    ('adviknair@mock.closetalk.local', 'Advik Nair', 'adviknair', 'Mock contact for development', 'mock', 'mock:adviknair'),
    ('tanishqdesai@mock.closetalk.local', 'Tanishq Desai', 'tanishqdesai', 'Mock contact for development', 'mock', 'mock:tanishqdesai'),
    ('ishamalhotra@mock.closetalk.local', 'Isha Malhotra', 'ishamalhotra', 'Mock contact for development', 'mock', 'mock:ishamalhotra')
ON CONFLICT (username) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    bio = EXCLUDED.bio,
    updated_at = now();

ALTER TABLE contacts DROP CONSTRAINT IF EXISTS contacts_status_check;
ALTER TABLE contacts ADD CONSTRAINT contacts_status_check
    CHECK (status IN ('pending','sent','accepted','blocked','rejected'));

DO $$
DECLARE
    pair RECORD;
    conv_id UUID;
BEGIN
    FOR pair IN
        SELECT DISTINCT
            LEAST(u.id, m.id) AS user_a,
            GREATEST(u.id, m.id) AS user_b
        FROM users m
        JOIN users u ON u.id <> m.id
        WHERE m.oauth_provider = 'mock'
          AND m.deleted_at IS NULL
          AND u.deleted_at IS NULL
    LOOP
        SELECT c.id INTO conv_id
        FROM conversations c
        JOIN conversation_participants p1 ON p1.conversation_id = c.id AND p1.user_id = pair.user_a
        JOIN conversation_participants p2 ON p2.conversation_id = c.id AND p2.user_id = pair.user_b
        WHERE c.type = 'direct'
        LIMIT 1;

        IF conv_id IS NULL THEN
            INSERT INTO conversations (type) VALUES ('direct') RETURNING id INTO conv_id;
            INSERT INTO conversation_participants (conversation_id, user_id)
            VALUES (conv_id, pair.user_a), (conv_id, pair.user_b)
            ON CONFLICT DO NOTHING;
        END IF;

        INSERT INTO contacts (user_id, contact_id, status, conversation_id)
        VALUES
            (pair.user_a, pair.user_b, 'accepted', conv_id),
            (pair.user_b, pair.user_a, 'accepted', conv_id)
        ON CONFLICT (user_id, contact_id) DO UPDATE SET
            status = CASE
                WHEN contacts.status = 'blocked' THEN contacts.status
                ELSE 'accepted'
            END,
            conversation_id = CASE
                WHEN contacts.status = 'blocked' THEN contacts.conversation_id
                ELSE EXCLUDED.conversation_id
            END,
            updated_at = now();

        conv_id := NULL;
    END LOOP;
END $$;

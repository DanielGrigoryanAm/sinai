-- Users, sessions and devices.

CREATE TABLE users (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name        text NOT NULL DEFAULT '' CHECK (char_length(name) <= 40),
    photo_url   text,
    created_at  timestamptz NOT NULL DEFAULT now(),
    last_seen   timestamptz
);

-- Long-lived sessions. Only a hash of the token is stored; each refresh
-- replaces the token, and reusing an old one is refused.
CREATE TABLE refresh_tokens (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash  bytea NOT NULL UNIQUE,
    created_at  timestamptz NOT NULL DEFAULT now(),
    expires_at  timestamptz NOT NULL,
    revoked_at  timestamptz
);
CREATE INDEX refresh_tokens_user ON refresh_tokens (user_id);

-- Push tokens (FCM / APNs) of each device.
CREATE TABLE device_tokens (
    token       text PRIMARY KEY,
    user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    platform    text NOT NULL CHECK (platform IN ('ios', 'android', 'web')),
    updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX device_tokens_user ON device_tokens (user_id);

-- Chats, joined by their short code.

CREATE TABLE chats (
    code        text PRIMARY KEY CHECK (code ~ '^[A-Z0-9]{6}$'),
    owner_id    uuid NOT NULL REFERENCES users(id),
    name        text NOT NULL DEFAULT '' CHECK (char_length(name) <= 40),
    photo_url   text,
    -- The mini game being played and the one picked, as the app keeps it.
    game        jsonb,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE chat_members (
    chat_code   text NOT NULL REFERENCES chats(code) ON DELETE CASCADE,
    user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    joined_at   timestamptz NOT NULL DEFAULT now(),
    -- Read up to here; drives "seen" and unread counts.
    read_at     timestamptz,
    PRIMARY KEY (chat_code, user_id)
);
CREATE INDEX chat_members_user ON chat_members (user_id);

-- Messages.

CREATE TABLE messages (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_code       text NOT NULL REFERENCES chats(code) ON DELETE CASCADE,
    sender_id       uuid REFERENCES users(id) ON DELETE SET NULL,
    -- Kept so messages of deleted accounts still show a name.
    sender_name     text NOT NULL DEFAULT '',
    text            text NOT NULL DEFAULT '',
    image_url       text,
    image_width     int,
    image_height    int,
    audio_url       text,
    audio_ms        int,
    reply_to        uuid REFERENCES messages(id) ON DELETE SET NULL,
    forwarded_from  text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    edited_at       timestamptz
);
-- History is read newest first, a page at a time.
CREATE INDEX messages_chat_time ON messages (chat_code, created_at DESC, id DESC);

CREATE TABLE message_reactions (
    message_id  uuid NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    emoji       text NOT NULL CHECK (char_length(emoji) <= 16),
    created_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (message_id, user_id)
);

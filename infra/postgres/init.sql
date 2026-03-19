-- Enable UUID extension for secure, non-sequential IDs
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. Users Table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    passwd_hash TEXT NOT NULL,
    name VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    gender VARCHAR(20),
    fcm_token VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Entities Tables (Master Lists for Categories)
CREATE TABLE materialistic_entities (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) UNIQUE NOT NULL,
    total_score BIGINT DEFAULT 0,
    users_votes INT DEFAULT 0
);

CREATE TABLE emotional_entities (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) UNIQUE NOT NULL,
    total_score BIGINT DEFAULT 0,
    users_votes INT DEFAULT 0
);

-- 3. Relationships Table (The "Pair" Bridge)
CREATE TABLE user_relationships (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_a_id UUID REFERENCES users(id),
    user_b_id UUID REFERENCES users(id),
    initiator_id UUID REFERENCES users(id), -- Who sent the request
    status VARCHAR(20) DEFAULT 'PENDING', -- PENDING, ACCEPTED, REJECTED
    reciprocity_score DECIMAL DEFAULT 0.0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_a_id, user_b_id) -- Prevents duplicate pairs
);

-- 4. Commitments Table (The Ledger)
CREATE TABLE commitments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    rel_id UUID REFERENCES user_relationships(id),
    initiator_id UUID REFERENCES users(id),
    target_id UUID REFERENCES users(id),
    entity_id UUID, -- Links to either materialistic or emotional (Optional now)
    entity_type VARCHAR(20), -- 'MATERIAL' or 'EMOTIONAL' (Optional now)
    text TEXT,
    category VARCHAR(20), -- emotional, money, help, health, other
    points INT,
    rating INT CHECK (rating >= 1 AND rating <= 100),
    status VARCHAR(20) DEFAULT 'PENDING', -- PENDING, ACKNOWLEDGED, FLAKED
    effort INT,
    time_taken INT,
    sacrifice INT,
    urgency INT,
    intensity DECIMAL,
    explanation TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 5. Outbox Events Table
CREATE TABLE outbox_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    aggregate_type VARCHAR(50) NOT NULL,
    aggregate_id UUID NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    payload JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
import os, sys, dotenv, psycopg2
from datetime import datetime, timedelta

sys.stdout.reconfigure(encoding='utf-8')
dotenv.load_dotenv('.env')
db_url = os.environ.get('DATABASE_URL')
if not db_url:
    print("Error: DATABASE_URL not found")
    sys.exit(1)

conn = psycopg2.connect(db_url)
cur = conn.cursor()

print("💬 Seeding realistic classmate conversations and messages for Akshu...")

# User IDs:
# 2: Akshu
# 10: AIT Star Student
# 40: Maya Sharma
# 41: Leo D'Souza
# 42: Samantha Rao

CONVERSATIONS = [
    {
        "peer_id": 10,
        "peer_name": "AIT Star Student",
        "messages": [
            (10, "Hey Akshu! Did you finish testing the obstacle-avoiding robot sensor? 🤖", 120),
            (2, "Yes! The ultrasonic distance threshold is working perfectly now.", 95),
            (10, "Awesome! Upload a clip or reel of it navigating on the floor.", 60),
            (2, "Done! Just shared it to my feed with the Python source snippet.", 25),
            (10, "Just saw it and liked it! Great work 🌟", 5)
        ]
    },
    {
        "peer_id": 40,
        "peer_name": "Maya Sharma",
        "messages": [
            (40, "Hi Akshu! Have you seen the latest James Webb Space Telescope pictures? 🔭", 180),
            (2, "Yes! The Pillars of Creation in mid-infrared look unbelievable.", 150),
            (40, "I posted a fun astronomy quiz question on my story as well.", 40),
            (2, "Checked it out! A day on Venus really is longer than a year on Venus!", 10)
        ]
    },
    {
        "peer_id": 41,
        "peer_name": "Leo D'Souza",
        "messages": [
            (41, "Hey Akshu, are you ready for the major project viva next week? 🎓", 300),
            (2, "Almost ready! Finalizing the parent digital guardian pulse and UI demo.", 240),
            (41, "The real-time multimodal safety filters will definitely impress the evaluators.", 120),
            (2, "Thanks Leo! Let's do a quick mock rehearsal tomorrow.", 30)
        ]
    }
]

for c_data in CONVERSATIONS:
    peer_id = c_data["peer_id"]
    child1_id = min(2, peer_id)
    child2_id = max(2, peer_id)

    # Check if conversation already exists
    cur.execute("""
        SELECT conversation_id FROM child_conversations 
        WHERE child1_id = %s AND child2_id = %s
    """, (child1_id, child2_id))
    row = cur.fetchone()

    if row:
        conv_id = row[0]
        print(f"  Conversation with {c_data['peer_name']} already exists (id={conv_id})")
    else:
        cur.execute("""
            INSERT INTO child_conversations (child1_id, child2_id, created_at)
            VALUES (%s, %s, NOW() - INTERVAL '3 days')
            RETURNING conversation_id
        """, (child1_id, child2_id))
        conv_id = cur.fetchone()[0]
        print(f"  Created conversation with {c_data['peer_name']} (id={conv_id})")

    # Ensure mutual followers exist
    for f_from, f_to in [(2, peer_id), (peer_id, 2)]:
        cur.execute("""
            INSERT INTO followers (child_id, following_child_id, approved, created_at)
            VALUES (%s, %s, TRUE, NOW() - INTERVAL '5 days')
            ON CONFLICT (child_id, following_child_id) DO UPDATE SET approved = TRUE
        """, (f_from, f_to))

    # Add messages if none exist
    cur.execute("SELECT COUNT(*) FROM child_messages WHERE conversation_id = %s", (conv_id,))
    msg_count = cur.fetchone()[0]
    if msg_count == 0:
        for sender_id, text, mins_ago in c_data["messages"]:
            receiver_id = peer_id if sender_id == 2 else 2
            sent_time = datetime.now() - timedelta(minutes=mins_ago)
            cur.execute("""
                INSERT INTO child_messages (
                    conversation_id, sender_child_id, receiver_child_id,
                    message_type, message_text, moderation_status,
                    is_deleted, is_seen, delivered_at, seen_at, sent_at
                ) VALUES (
                    %s, %s, %s,
                    'TEXT', %s, 'ALLOWED',
                    FALSE, TRUE, %s, %s, %s
                )
            """, (conv_id, sender_id, receiver_id, text, sent_time, sent_time, sent_time))
        print(f"    Inserted {len(c_data['messages'])} safe messages for conversation {conv_id}")

conn.commit()
cur.close()
conn.close()
print("✅ Done! Classmate conversations seeded successfully.")
